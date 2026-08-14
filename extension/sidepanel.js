'use strict';

// ===== 多言語化 =====
// 拡張として動いているときは chrome.i18n を使う。
// プレビュー（chrome が無い開発用サーバー）では _locales/ja/messages.json を読んで同じ関数で引く
const hasChromeI18n = typeof chrome !== 'undefined' && chrome.i18n && chrome.i18n.getMessage;
let previewMessages = null;

function uiLanguage() {
  if (hasChromeI18n && chrome.i18n.getUILanguage) return chrome.i18n.getUILanguage();
  return 'ja';
}

function isJapaneseUI() {
  return uiLanguage().toLowerCase().startsWith('ja');
}

// $1・$2… の位置に値を差し込む。chrome.i18n と同じ書式を自前でも解釈する
function T(key, ...subs) {
  if (hasChromeI18n) {
    const s = subs.map(String);
    return chrome.i18n.getMessage(key, s.length ? s : undefined) || key;
  }
  const entry = previewMessages && previewMessages[key];
  if (!entry) return key;
  return entry.message.replace(/\$(\d)/g, (m, n) => {
    const v = subs[Number(n) - 1];
    return v === undefined ? m : String(v);
  });
}

async function loadPreviewMessages() {
  if (hasChromeI18n) return;
  try {
    previewMessages = await (await fetch('_locales/ja/messages.json')).json();
  } catch {
    // 読めなくてもキー名がそのまま出るだけ。拡張としての動作には影響しない
  }
}

function applyI18n() {
  for (const el of document.querySelectorAll('[data-i18n]')) {
    el.textContent = T(el.dataset.i18n);
  }
  for (const el of document.querySelectorAll('[data-i18n-title]')) {
    el.title = T(el.dataset.i18nTitle);
  }
  for (const el of document.querySelectorAll('[data-i18n-placeholder]')) {
    el.placeholder = T(el.dataset.i18nPlaceholder);
  }
  for (const el of document.querySelectorAll('[data-i18n-aria-label]')) {
    el.setAttribute('aria-label', T(el.dataset.i18nAriaLabel));
  }
  document.documentElement.lang = uiLanguage();
}

// ===== ストレージ抽象化 =====
// 拡張機能内では chrome.storage.local、通常ブラウザ（開発プレビュー）では localStorage を使う
const storage = (() => {
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    return {
      async get() {
        const data = await chrome.storage.local.get('templates');
        return data.templates || [];
      },
      async set(templates) {
        await chrome.storage.local.set({ templates });
      },
      async getRaw(key) {
        return (await chrome.storage.local.get(key))[key];
      },
      async setRaw(key, value) {
        await chrome.storage.local.set({ [key]: value });
      },
    };
  }
  return {
    async get() {
      try {
        return JSON.parse(localStorage.getItem('templates')) || [];
      } catch {
        return [];
      }
    },
    async set(templates) {
      localStorage.setItem('templates', JSON.stringify(templates));
    },
    async getRaw(key) {
      try {
        return JSON.parse(localStorage.getItem(key)) || undefined;
      } catch {
        return undefined;
      }
    },
    async setRaw(key, value) {
      localStorage.setItem(key, JSON.stringify(value));
    },
  };
})();

// ===== 状態 =====
let templates = [];
let filtered = [];
let selectedIndex = -1;
let editingId = null; // null = 新規追加

// ===== DOM =====
const $ = (id) => document.getElementById(id);
const viewList = $('viewList');
const viewEdit = $('viewEdit');
const viewIO = $('viewIO');
const searchInput = $('searchInput');
const categoryFilter = $('categoryFilter');
const templateList = $('templateList');
const listMeta = $('listMeta');
const emptyState = $('emptyState');
const noResults = $('noResults');

// ===== ユーティリティ =====
function uuid() {
  return crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2);
}

let toastTimer = null;
function showToast(message, isError = false) {
  const toast = $('toast');
  toast.textContent = message;
  toast.classList.toggle('error', isError);
  toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.hidden = true;
  }, 1800);
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // クリップボードAPIが使えない場合のフォールバック
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try {
      ok = document.execCommand('copy');
    } catch {
      ok = false;
    }
    ta.remove();
    return ok;
  }
}

// ===== ビュー切り替え =====
function showView(name) {
  // 編集中に他のウィンドウの変更を反映すると入力が消えるので、離れるまで待たせている
  if (name !== 'edit') applyPendingTemplates();
  viewList.hidden = name !== 'list';
  viewEdit.hidden = name !== 'edit';
  viewIO.hidden = name !== 'io';
  if (name === 'list') {
    searchInput.focus();
  }
  // 入出力画面を開くたびに、取り消せる操作の表示を最新にする
  if (name === 'io') refreshUndoUI();
}

// ===== 元に戻す =====
// 破壊的な操作の直前の状態を1つだけ保持する。版管理までは持たず、
// 「直前のやらかしを取り消す」1段に絞っている
const UNDO_KEY = 'undoSnapshot';

// 変更を加える「前」に呼ぶこと。
// isUndo は「この状態に戻すと、いま取り消した操作をやり直すことになる」という印
async function captureUndo(label, isUndo = false) {
  try {
    await storage.setRaw(UNDO_KEY, {
      templates: JSON.parse(JSON.stringify(templates)),
      label,
      at: Date.now(),
      isUndo,
    });
  } catch {
    // 記録できなくても本来の操作は続行させる
  }
}

function formatUndoTime(at) {
  const d = new Date(at);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}/${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function refreshUndoUI() {
  let snapshot;
  try {
    snapshot = await storage.getRaw(UNDO_KEY);
  } catch {
    snapshot = undefined;
  }
  const btn = $('btnUndo');
  const info = $('undoInfo');
  if (!snapshot || !Array.isArray(snapshot.templates)) {
    btn.hidden = true;
    info.textContent = T('undoNone');
    return;
  }
  btn.hidden = false;
  btn.textContent = T(snapshot.isUndo ? 'btnRedo' : 'btnUndo');
  info.textContent = T(
    snapshot.isUndo ? 'redoAvailable' : 'undoAvailable',
    snapshot.label,
    formatUndoTime(snapshot.at)
  );
}

async function performUndo() {
  let snapshot;
  try {
    snapshot = await storage.getRaw(UNDO_KEY);
  } catch {
    snapshot = undefined;
  }
  if (!snapshot || !Array.isArray(snapshot.templates)) {
    showToast(T('toastNothingToUndo'), true);
    await refreshUndoUI();
    return;
  }

  // 取り消し自体もやり直せるように、いまの状態を新しいスナップショットにする。
  // isUndo を反転させることで「取り消す」と「やり直す」を行き来できる
  await captureUndo(snapshot.label, !snapshot.isUndo);
  templates = snapshot.templates;
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  await refreshUndoUI();
  showToast(T(snapshot.isUndo ? 'toastRedone' : 'toastUndone', snapshot.label));
}

// ===== 別ウィンドウ表示 =====
// サイドパネルはChromeの仕様で枠から切り離せないため、独立したウィンドウで開く手段を用意する。
// chrome.windows は権限宣言なしで使えるので、権限は sidePanel / storage のまま増えない。
// （既存ウィンドウの再利用も、URL検索ではなくウィンドウIDの記憶で済ませて tabs 権限を避けている）
const WINDOW_WIDTH = 400;
const WINDOW_HEIGHT = 700;
const POPUP_ID_KEY = 'popupWindowId';
// サイドパネルに戻すとき、開いたときと同じウィンドウに戻すために覚えておく
const ORIGIN_ID_KEY = 'popupOriginWindowId';
const isPopupWindow = new URLSearchParams(location.search).get('view') === 'window';
// まとめるくん（自作のハブ拡張）の iframe 内で動いているとき。
// ハブ側の窓がすでに「切り離された1枚」なので、こちらの切り離し・移譲は全部黙らせる
const isEmbedded = window.self !== window.top;
const canOpenWindow = typeof chrome !== 'undefined' && !!chrome.windows && !!chrome.runtime;

async function ensureWindow() {
  // すでに開いているウィンドウがあれば、新しく作らずに前面へ出す
  try {
    const saved = await chrome.storage.local.get(POPUP_ID_KEY);
    const id = saved[POPUP_ID_KEY];
    if (id != null) {
      await chrome.windows.update(id, { focused: true, drawAttention: true });
      return true;
    }
  } catch {
    // 閉じられているとIDが無効になる。そのまま新規作成に進む
  }

  const options = {
    url: chrome.runtime.getURL('sidepanel.html') + '?view=window',
    type: 'popup',
    width: WINDOW_WIDTH,
    height: WINDOW_HEIGHT,
  };
  // いま自分が入っているウィンドウ。位置の基準にもなるし、戻り先としても覚えておく
  const base = await getOwnWindow();
  if (base && typeof base.left === 'number' && typeof base.width === 'number') {
    options.left = Math.max(0, base.left + base.width - WINDOW_WIDTH - 20);
    options.top = Math.max(0, (base.top || 0) + 20);
  }

  try {
    const created = await chrome.windows.create(options);
    // 閉じる前にIDを確実に保存する（保存前にパネルを閉じると次回の再利用ができなくなる）
    const toSave = { [POPUP_ID_KEY]: created.id };
    if (base && base.type === 'normal') toSave[ORIGIN_ID_KEY] = base.id;
    await chrome.storage.local.set(toSave);
    return true;
  } catch {
    showToast(T('toastWindowFailed'), true);
    return false;
  }
}

// 自分が属しているウィンドウを取る。getCurrent が使えない場合に備えて getLastFocused に落とす
async function getOwnWindow() {
  try {
    return await chrome.windows.getCurrent();
  } catch {
    try {
      return await chrome.windows.getLastFocused();
    } catch {
      return null;
    }
  }
}

// サイドパネルを開き直す先を決める。開いたときと同じウィンドウを最優先にする
async function findSidePanelTarget() {
  try {
    const saved = await chrome.storage.local.get(ORIGIN_ID_KEY);
    const originId = saved[ORIGIN_ID_KEY];
    if (originId != null) {
      const origin = await chrome.windows.get(originId);
      if (origin && origin.type === 'normal') return origin;
    }
  } catch {
    // 元のウィンドウが閉じられている。下のフォールバックへ
  }

  try {
    const normals = (await chrome.windows.getAll()).filter((w) => w.type === 'normal');
    return normals.find((w) => w.focused) || normals[0] || null;
  } catch {
    return null;
  }
}

async function openInWindow() {
  // 同じものがサイドパネルと別ウィンドウに2つ並ぶと分かりにくいので、
  // 別ウィンドウを開けたらサイドパネルのほうは閉じる
  if (await ensureWindow()) window.close();
}

// 別ウィンドウからサイドパネルへ戻す。
// 順序が重要で、記憶しているウィンドウIDを消してから chrome.sidePanel.open() を呼ぶ。
// IDが残ったままだと、開いたサイドパネルが handOverToExistingWindow() で
// 「別ウィンドウが生きている」と判断して即座に自分を閉じてしまう
async function returnToSidePanel() {
  // populate を付けずにウィンドウを見るだけなので tabs 権限は要らない
  const target = await findSidePanelTarget();
  const self = await getOwnWindow();

  if (!target) {
    showToast(T('toastNoBrowserWindow'), true);
    return;
  }

  try {
    await chrome.storage.local.remove([POPUP_ID_KEY, ORIGIN_ID_KEY]);
  } catch {
    // 消せなくても続行する（最悪サイドパネルが閉じるだけで、このウィンドウは残る）
  }

  try {
    await chrome.sidePanel.open({ windowId: target.id });
  } catch {
    // 開けなかったらIDを戻して、この別ウィンドウをそのまま使い続けられるようにする
    if (self) {
      try {
        await chrome.storage.local.set({ [POPUP_ID_KEY]: self.id, [ORIGIN_ID_KEY]: target.id });
      } catch {
        // 戻せない場合は二重表示になりうるが、実害は表示だけ
      }
    }
    showToast(T('toastSidePanelFailed'), true);
    return;
  }

  // サイドパネルはブラウザ側のウィンドウに出るので、そちらを前面に持ってくる
  try {
    await chrome.windows.update(target.id, { focused: true });
  } catch {
    // 前面化に失敗しても閉じてよい
  }
  window.close();
}

// サイドパネルとして開かれたとき、すでに別ウィンドウが生きていればそちらへ寄せる。
// ツールバーのアイコンから開いた場合も2つ並ばないようにするため
async function handOverToExistingWindow() {
  if (isPopupWindow || isEmbedded || !canOpenWindow) return false;
  let id;
  try {
    const saved = await chrome.storage.local.get(POPUP_ID_KEY);
    id = saved[POPUP_ID_KEY];
  } catch {
    return false;
  }
  if (id == null) return false;

  try {
    await chrome.windows.update(id, { focused: true, drawAttention: true });
  } catch {
    // すでに閉じられている。古いIDを捨てて、サイドパネルをそのまま使う
    try {
      await chrome.storage.local.remove([POPUP_ID_KEY, ORIGIN_ID_KEY]);
    } catch {
      // 消せなくても実害はない（次回 update が失敗して同じ経路に来るだけ）
    }
    return false;
  }
  window.close();
  return true;
}

// ===== 他のウィンドウとの同期 =====
// サイドパネルと別ウィンドウを同時に開けるので、片方の変更をもう片方に反映する
let pendingTemplates = null;

function applyPendingTemplates() {
  if (!pendingTemplates) return;
  templates = pendingTemplates;
  pendingTemplates = null;
  renderCategoryOptions();
  applyFilter();
}

if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.onChanged) {
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local') return;
    // もう片方の画面で操作されたら、取り消せる内容の表示も合わせる
    if (changes[UNDO_KEY] && !viewIO.hidden) refreshUndoUI();
    if (!changes.templates) return;
    pendingTemplates = changes.templates.newValue || [];
    if (viewEdit.hidden) applyPendingTemplates();
  });
}

// ===== カテゴリ =====
function getCategories() {
  const set = new Set();
  for (const t of templates) {
    if (t.category && t.category.trim()) set.add(t.category.trim());
  }
  return [...set].sort((a, b) => a.localeCompare(b, 'ja'));
}

function renderCategoryOptions() {
  const categories = getCategories();
  const current = categoryFilter.value;
  categoryFilter.innerHTML = '';
  const all = document.createElement('option');
  all.value = '';
  all.textContent = T('allCategories');
  categoryFilter.appendChild(all);
  const datalist = $('categoryList');
  datalist.innerHTML = '';
  for (const c of categories) {
    const opt = document.createElement('option');
    opt.value = c;
    opt.textContent = c;
    categoryFilter.appendChild(opt);
    datalist.appendChild(opt.cloneNode(true));
  }
  // 絞り込み中のカテゴリが消えていなければ維持する
  if (categories.includes(current)) categoryFilter.value = current;
}

// ===== 検索・一覧表示 =====
function applyFilter() {
  const q = searchInput.value.trim().toLowerCase();
  const cat = categoryFilter.value;
  filtered = templates.filter((t) => {
    if (cat && t.category !== cat) return false;
    if (!q) return true;
    return (
      t.title.toLowerCase().includes(q) ||
      t.body.toLowerCase().includes(q) ||
      t.category.toLowerCase().includes(q)
    );
  });
  // 検索中はEnterですぐコピーできるよう先頭を選択しておく
  selectedIndex = q || cat ? (filtered.length > 0 ? 0 : -1) : -1;
  renderList();
}

function renderList() {
  templateList.innerHTML = '';
  const fragment = document.createDocumentFragment();

  filtered.forEach((t, i) => {
    const li = document.createElement('li');
    li.className = 'template-item' + (i === selectedIndex ? ' selected' : '');
    li.dataset.id = t.id;

    const top = document.createElement('div');
    top.className = 'item-top';
    if (t.category) {
      const cat = document.createElement('span');
      cat.className = 'item-category';
      cat.textContent = t.category;
      top.appendChild(cat);
    }
    const title = document.createElement('span');
    title.className = 'item-title';
    title.textContent = t.title || T('untitled');
    top.appendChild(title);
    li.appendChild(top);

    const preview = document.createElement('div');
    preview.className = 'item-preview';
    // 空行で行数を消費しないよう、プレビューでは改行をスペースに畳む
    preview.textContent = t.body.replace(/\s*\n\s*/g, ' ').trim();
    li.appendChild(preview);

    // 一覧では本文が2行までしか出ないので、全文を読むための入口を用意する。
    // 開いた先で編集も保存もコピーもできる
    const detailBtn = document.createElement('button');
    detailBtn.className = 'item-detail-btn';
    detailBtn.textContent = T('detailBtn');
    detailBtn.title = T('detailBtnTip');
    detailBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      openEdit(t.id);
    });
    li.appendChild(detailBtn);

    li.addEventListener('click', () => copyTemplate(t, li));
    fragment.appendChild(li);
  });

  templateList.appendChild(fragment);

  emptyState.hidden = templates.length !== 0;
  noResults.hidden = !(templates.length > 0 && filtered.length === 0);
  listMeta.textContent =
    templates.length === 0
      ? ''
      : filtered.length === templates.length
        ? T('countAll', templates.length)
        : T('countFiltered', filtered.length, templates.length);
}

async function copyTemplate(t, element) {
  const ok = await copyText(t.body);
  if (ok) {
    showToast(T('toastCopied', t.title || T('untitled')));
    if (element) {
      element.classList.add('copied');
      setTimeout(() => element.classList.remove('copied'), 700);
    }
  } else {
    showToast(T('toastCopyFailed'), true);
  }
}

// ===== キーボード操作 =====
function moveSelection(delta) {
  if (filtered.length === 0) return;
  selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta));
  const items = templateList.children;
  for (let i = 0; i < items.length; i++) {
    items[i].classList.toggle('selected', i === selectedIndex);
  }
  if (items[selectedIndex]) {
    items[selectedIndex].scrollIntoView({ block: 'nearest' });
  }
}

document.addEventListener('keydown', (e) => {
  if (!viewEdit.hidden || !viewIO.hidden) return; // 一覧ビュー表示中のみ
  if (e.isComposing) return; // 日本語変換中は無視
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    moveSelection(1);
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    moveSelection(-1);
  } else if (e.key === 'Enter') {
    if (selectedIndex >= 0 && filtered[selectedIndex]) {
      e.preventDefault();
      copyTemplate(filtered[selectedIndex], templateList.children[selectedIndex]);
    }
  } else if (e.key === 'Escape') {
    if (searchInput.value) {
      searchInput.value = '';
      applyFilter();
    }
    searchInput.focus();
  }
});

// ===== 追加・編集・削除 =====
function openEdit(id) {
  editingId = id || null;
  const t = id ? templates.find((x) => x.id === id) : null;
  // 全文を読むために開くことも多いので、見出しは「編集」と言い切らない
  $('editHeading').textContent = T(t ? 'editHeadingExisting' : 'editHeadingNew');
  $('btnCopyBody').hidden = !t;
  $('editCategory').value = t ? t.category : categoryFilter.value || '';
  $('editTitle').value = t ? t.title : '';
  $('editBody').value = t ? t.body : '';
  editJustSaved = false;
  setEditBaseline();
  updateEditState();
  showView('edit');
  $('editTitle').focus();
}

// 画面を開いた（または保存した）時点の内容。これと比べて「触ったかどうか」を判定する
let editBaseline = null;
let editJustSaved = false;

function snapshotForm() {
  return { category: $('editCategory').value, title: $('editTitle').value, body: $('editBody').value };
}

function setEditBaseline() {
  editBaseline = snapshotForm();
}

function hasUnsavedChanges() {
  if (!editBaseline) return false;
  const now = snapshotForm();
  return (
    now.category !== editBaseline.category || now.title !== editBaseline.title || now.body !== editBaseline.body
  );
}

function fillForm(source) {
  $('editCategory').value = source.category;
  $('editTitle').value = source.title;
  $('editBody').value = source.body;
}

// 編集画面のボタンとバーの出し分け。
// 触っていなければ保存ボタンを出さないので、保存が現れること自体が
// 「何か変えた」という合図になる
function updateEditState() {
  const notice = $('editNotice');
  const dirty = hasUnsavedChanges();
  if (dirty) editJustSaved = false;

  $('btnDelete').hidden = editJustSaved || !editingId;
  $('btnSave').hidden = !dirty;
  $('btnEditUndo').hidden = !editJustSaved;
  $('btnRevertEdit').hidden = !dirty;

  if (editJustSaved) {
    notice.hidden = false;
    notice.className = 'edit-notice saved';
  } else if (dirty) {
    notice.hidden = false;
    notice.className = 'edit-notice dirty';
    $('editNoticeText').textContent = T('noticeDirty');
  } else {
    notice.hidden = true;
  }
}

// 保存前の入力を捨てて、開いた（または最後に保存した）時点の内容に戻す
function revertEdit() {
  if (!editBaseline) return;
  fillForm(editBaseline);
  updateEditState();
  showToast(T('toastReverted'));
}

function leaveEdit() {
  if (hasUnsavedChanges() && !confirm(T('confirmLeave'))) return;
  showView('list');
}

async function saveEdit() {
  const category = $('editCategory').value.trim();
  const title = $('editTitle').value.trim();
  const body = $('editBody').value;
  if (!title && !body.trim()) {
    showToast(T('toastNeedInput'), true);
    return;
  }
  const shownTitle = title || T('untitled');
  const isNew = !editingId;
  await captureUndo(T(isNew ? 'labelAdd' : 'labelEdit', shownTitle));

  const now = Date.now();
  if (editingId) {
    const t = templates.find((x) => x.id === editingId);
    if (t) {
      t.category = category;
      t.title = title;
      t.body = body;
      t.updatedAt = now;
    }
  } else {
    const created = { id: uuid(), category, title, body, createdAt: now, updatedAt: now };
    templates.unshift(created);
    // 保存後もこの画面に留まるので、次に保存したとき二重登録にならないよう対象を切り替える
    editingId = created.id;
    $('editHeading').textContent = T('editHeadingExisting');
    $('btnCopyBody').hidden = false;
  }
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();

  // 保存で前後の空白を落としているので、画面も保存後の内容に揃えてから基準にする
  const saved = templates.find((x) => x.id === editingId);
  if (saved) fillForm(saved);

  // 一覧には戻らず、この場で取り消せるようにする
  $('editNoticeText').textContent = T(isNew ? 'noticeSavedAdd' : 'noticeSavedEdit', shownTitle);
  editJustSaved = true;
  setEditBaseline();
  updateEditState();
  showToast(T('toastSaved'));
}

// 編集画面から直前の保存を取り消す
async function undoFromEdit() {
  await performUndo();
  editJustSaved = false;
  const t = editingId ? templates.find((x) => x.id === editingId) : null;
  if (!t) {
    // 追加そのものを取り消した場合は、この定型文がもう存在しない
    showView('list');
    return;
  }
  fillForm(t);
  setEditBaseline();
  updateEditState();
}

async function deleteEditing() {
  if (!editingId) return;
  const t = templates.find((x) => x.id === editingId);
  const shownTitle = (t && t.title) || T('untitled');
  if (!confirm(T('confirmDelete', shownTitle))) return;
  await captureUndo(T('labelDelete', shownTitle));
  templates = templates.filter((x) => x.id !== editingId);
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showView('list');
  showToast(T('toastDeleted'));
}

// ===== CSV / TSV パーサー（ここから）=====
// スプレッドシートの範囲コピーとファイル読み込みの両方で共用する。
// ダブルクォート囲み（改行・区切り文字入りセル、"" エスケープ）にも対応する
const TAB = '\t';
const COMMA = ',';

// Excel由来のCSVは先頭にBOMが付くことがあるので取り除く
function stripBOM(text) {
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

function parseDelimited(text, delimiter) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else if (c === '\r') {
        // セル内の改行もCRLF／CRをLFに揃える（\rが本文に残るとコピー時に混ざるため）
        if (text[i + 1] === '\n') i++;
        field += '\n';
      } else {
        field += c;
      }
    } else if (c === '"' && field === '') {
      inQuotes = true;
    } else if (c === delimiter) {
      row.push(field);
      field = '';
    } else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++; // CRLFは1つの改行として扱う
      row.push(field);
      field = '';
      rows.push(row);
      row = [];
    } else {
      field += c;
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((f) => f.trim() !== ''));
}

// 区切り文字の判定。拡張子で分かるならそれを使い、分からなければ先頭行のタブとカンマを数える。
// reason は表示用の文言ではなく手掛かりの種類を返す（このブロックは Node のテストから直接呼ばれるため、
// 画面に出す文言はここでは組み立てない）
function detectDelimiter(text, filename = '') {
  const ext = filename.toLowerCase().match(/\.([a-z0-9]+)$/);
  if (ext && ext[1] === 'csv') return { delimiter: COMMA, reason: 'ext' };
  if (ext && ext[1] === 'tsv') return { delimiter: TAB, reason: 'ext' };

  let tabs = 0;
  let commas = 0;
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') i++;
        else inQuotes = false;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === TAB) {
      tabs++;
    } else if (c === COMMA) {
      commas++;
    } else if (c === '\n' || c === '\r') {
      break; // 先頭行だけを見る
    }
  }
  // 同数（どちらも0を含む）ならタブ区切り扱い。スプレッドシート由来のTSVが既定のため
  return { delimiter: tabs >= commas ? TAB : COMMA, reason: 'firstLine' };
}

function delimitedField(s, delimiter) {
  return s.includes(delimiter) || /["\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

// ヘッダーは画面の言語に合わせて呼び出し側から渡す。既定は英語（Node のテストから直接呼ぶ場合用）。
// どちらの言語で書き出しても rowsToTemplates がヘッダー行として読み飛ばせる
function toDelimited(items, delimiter, headers = ['Category', 'Title', 'Body']) {
  const lines = [headers.map((h) => delimitedField(h, delimiter)).join(delimiter)];
  for (const t of items) {
    lines.push(
      [t.category || '', t.title || '', t.body || ''].map((f) => delimitedField(f, delimiter)).join(delimiter)
    );
  }
  return lines.join('\n');
}

// 解析済みの行を定型文に変換する。カテゴリ／概要／本文の3列に合わない行はスキップして数える
function rowsToTemplates(rows) {
  // ヘッダー行らしき先頭行はスキップする
  if (rows.length > 0) {
    const h = rows[0].map((f) => f.trim().toLowerCase());
    if (h[0] === 'カテゴリ' || h[0] === 'category') rows = rows.slice(1);
  }
  const now = Date.now();
  const imported = [];
  let skipped = 0;
  for (const r of rows) {
    const cells = r.slice();
    // Excel由来のCSVは4列目以降に空セルが付くことがあるので、末尾の空セルだけ落とす
    while (cells.length > 3 && cells[cells.length - 1].trim() === '') cells.pop();
    if (cells.length !== 3) {
      skipped++;
      continue;
    }
    const t = {
      id: uuid(),
      category: cells[0].trim(),
      title: cells[1].trim(),
      body: cells[2],
      createdAt: now,
      updatedAt: now,
    };
    if (!t.title && !t.body.trim()) {
      skipped++;
      continue;
    }
    imported.push(t);
  }
  return { imported, skipped };
}
// ===== CSV / TSV パーサー（ここまで）=====

// 表示用の文言。パーサー本体（上のブロック）は Node のテストから切り出して実行されるので、
// T() を使う部分はブロックの外に置いている
function delimiterLabel(delimiter) {
  return T(delimiter === TAB ? 'delimTab' : 'delimComma');
}

function delimiterReasonLabel(reason) {
  return T(reason === 'ext' ? 'reasonExt' : 'reasonFirstLine');
}

function localizedHeaders() {
  return [T('headerCategory'), T('headerTitle'), T('headerBody')];
}

// 貼り付け・ファイル読み込みの共通処理。追記／置き換えの選択を適用して保存する
async function runImport(rows, { backToList }) {
  const { imported, skipped } = rowsToTemplates(rows);
  if (imported.length === 0) {
    const msg = skipped > 0 ? T('importNoRowsSkipped', skipped) : T('importNoRows');
    showToast(msg, true);
    return { ok: false, imported: 0, skipped, message: msg };
  }

  const mode = document.querySelector('input[name="importMode"]:checked').value;
  if (mode === 'replace') {
    if (!confirm(T('confirmReplace', templates.length, imported.length))) {
      return { ok: false, cancelled: true, imported: 0, skipped, message: T('importCancelled') };
    }
    await captureUndo(T('labelReplace', imported.length));
    templates = imported;
  } else {
    await captureUndo(T('labelImport', imported.length));
    templates = [...imported, ...templates];
  }
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  if (backToList) showView('list');

  const message =
    skipped > 0 ? T('importDoneSkipped', imported.length, skipped) : T('importDone', imported.length);
  showToast(message);
  return { ok: true, imported: imported.length, skipped, message };
}

// 貼り付けインポートはスプレッドシートの範囲コピーが前提なので、区切り文字はタブ固定
async function importPasted() {
  const text = $('importText').value;
  if (!text.trim()) {
    showToast(T('toastPasteEmpty'), true);
    return;
  }
  const result = await runImport(parseDelimited(stripBOM(text), TAB), { backToList: true });
  if (result.ok) $('importText').value = '';
}

// ===== ファイルからのインポート =====
function setFileStatus(text, isError = false) {
  const status = $('fileStatus');
  status.textContent = text;
  status.classList.toggle('error', isError);
  status.hidden = !text;
}

function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error || new Error('read error'));
    reader.readAsText(file, 'UTF-8');
  });
}

async function importFromFile(file) {
  if (!file) return;
  setFileStatus(T('fileReading', file.name));

  let text;
  try {
    text = stripBOM(await readFileAsText(file));
  } catch {
    setFileStatus(T('fileReadFailed', file.name), true);
    showToast(T('toastFileReadFailed'), true);
    return;
  }

  if (!text.trim()) {
    setFileStatus(T('fileEmpty', file.name), true);
    showToast(T('toastFileEmpty'), true);
    return;
  }

  const { delimiter, reason } = detectDelimiter(text, file.name);
  const label = delimiterLabel(delimiter);
  setFileStatus(T('fileDetecting', file.name, label, delimiterReasonLabel(reason)));

  const result = await runImport(parseDelimited(text, delimiter), { backToList: false });
  setFileStatus(T('fileDone', file.name, label, result.message), !result.ok);
}

// ===== エクスポート =====
function downloadFile(filename, content, mime) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function dateStamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
}

// ===== サンプル定型文 =====
// 画面の言語に合わせて出し分ける。日本語のサンプルは英語話者には読めず、
// ストアの審査担当者も英語ロケールで触るため、英語版を別に用意している
const SAMPLE_TEMPLATES_JA = [
  {
    category: '挨拶',
    title: '初回の挨拶（社外）',
    body: 'お世話になっております。\n株式会社〇〇の△△と申します。\n\nこの度は□□の件でご連絡いたしました。\n今後ともどうぞよろしくお願いいたします。',
  },
  {
    category: '依頼',
    title: '資料送付のお願い',
    body: 'お世話になっております。\n\n〇〇の件につきまして、関連資料をお送りいただけますでしょうか。\nお忙しいところ恐れ入りますが、□月□日までにいただけますと幸いです。\n\nよろしくお願いいたします。',
  },
  {
    category: '依頼',
    title: '確認のお願い',
    body: 'お世話になっております。\n\n先日お送りした〇〇について、ご確認いただけましたでしょうか。\nご不明な点がございましたら、お気軽にお知らせください。\n\nよろしくお願いいたします。',
  },
  {
    category: 'お礼',
    title: '打ち合わせのお礼',
    body: 'お世話になっております。\n\n本日はお忙しい中、お時間をいただきありがとうございました。\nいただいたご意見をもとに、〇〇を進めてまいります。\n\n引き続きよろしくお願いいたします。',
  },
  {
    category: '日程調整',
    title: '打ち合わせ日程の候補提示',
    body: 'お世話になっております。\n\n〇〇の打ち合わせにつきまして、下記の日程でご都合はいかがでしょうか。\n\n・□月□日（□）□:00〜\n・□月□日（□）□:00〜\n・□月□日（□）□:00〜\n\nご都合の良い日時をお知らせいただけますと幸いです。',
  },
  {
    category: '日程調整',
    title: '日程変更のお願い',
    body: 'お世話になっております。\n\n□月□日にお約束しておりました打ち合わせについて、誠に恐れ入りますが、都合により日程を変更させていただけないでしょうか。\n\n改めて候補日をお送りいたしますので、ご検討いただけますと幸いです。\nご迷惑をおかけして申し訳ございません。',
  },
  {
    category: '謝罪',
    title: '返信遅れのお詫び',
    body: 'お世話になっております。\n\nご連絡いただいておりました件、返信が遅くなり申し訳ございません。\n\n〇〇につきましては、下記のとおりです。\n\n今後ともよろしくお願いいたします。',
  },
  {
    category: '連絡',
    title: '添付ファイル送付',
    body: 'お世話になっております。\n\n〇〇の資料を添付にてお送りいたします。\nご確認のほど、よろしくお願いいたします。\n\n※添付：□□.pdf',
  },
  {
    category: '連絡',
    title: '不在のお知らせ',
    body: 'お世話になっております。\n\n誠に勝手ながら、□月□日（□）は終日不在にしております。\nお急ぎの場合は、△△（メール：xxx@example.com）までご連絡ください。\n\nご不便をおかけしますが、よろしくお願いいたします。',
  },
  {
    category: '社内',
    title: '会議リマインド',
    body: 'お疲れさまです。\n\n本日□:00より〇〇会議を行います。\n場所：△△（オンラインの場合はリンク参照）\n\n資料は事前に共有フォルダをご確認ください。\nよろしくお願いします。',
  },
];

const SAMPLE_TEMPLATES_EN = [
  {
    category: 'Greetings',
    title: 'First contact (external)',
    body: 'Hello,\n\nMy name is [your name] from [company]. I am getting in touch about [subject].\n\nI look forward to working with you.\n\nBest regards,\n[your name]',
  },
  {
    category: 'Requests',
    title: 'Asking for documents',
    body: 'Hello,\n\nCould you send over the material related to [subject]?\n\nIf you are able to get it to me by [date], that would be a great help.\n\nThank you,\n[your name]',
  },
  {
    category: 'Requests',
    title: 'Following up for a review',
    body: 'Hello,\n\nI wanted to check whether you have had a chance to look at [subject] that I sent over on [date].\n\nHappy to answer any questions.\n\nThank you,\n[your name]',
  },
  {
    category: 'Thanks',
    title: 'After a meeting',
    body: 'Hello,\n\nThank you for making time today. I appreciated the discussion.\n\nBased on what we agreed, I will move ahead with [next step] and come back to you by [date].\n\nBest regards,\n[your name]',
  },
  {
    category: 'Scheduling',
    title: 'Offering meeting times',
    body: 'Hello,\n\nWould any of the following work for a meeting about [subject]?\n\n- [date], [time]\n- [date], [time]\n- [date], [time]\n\nEach slot is about [duration]. Let me know which suits you and I will send an invitation.\n\nThank you,\n[your name]',
  },
  {
    category: 'Scheduling',
    title: 'Asking to reschedule',
    body: 'Hello,\n\nI am sorry to ask, but something has come up and I need to move our meeting on [date].\n\nI will send a few alternative times shortly. Apologies for the inconvenience.\n\nThank you for understanding,\n[your name]',
  },
  {
    category: 'Apologies',
    title: 'Late reply',
    body: 'Hello,\n\nApologies for the slow reply on [subject].\n\nHere is where things stand: [details]\n\nThank you for your patience,\n[your name]',
  },
  {
    category: 'Updates',
    title: 'Sending an attachment',
    body: 'Hello,\n\nPlease find the [subject] material attached.\n\nDo let me know if anything is unclear.\n\nBest regards,\n[your name]\n\nAttached: [filename]',
  },
  {
    category: 'Updates',
    title: 'Out of office',
    body: 'Hello,\n\nI will be away from my desk all day on [date].\n\nIf it is urgent, please contact [colleague] at [email].\n\nThank you,\n[your name]',
  },
  {
    category: 'Internal',
    title: 'Meeting reminder',
    body: 'Hi all,\n\nA reminder that the [subject] meeting starts at [time] today.\n\nWhere: [room, or the link in the invitation]\n\nThe material is in the shared folder — please take a look beforehand.\n\nThanks,\n[your name]',
  },
];

async function loadSamples() {
  const SAMPLE_TEMPLATES = isJapaneseUI() ? SAMPLE_TEMPLATES_JA : SAMPLE_TEMPLATES_EN;
  await captureUndo(T('labelSamples', SAMPLE_TEMPLATES.length));
  const now = Date.now();
  const items = SAMPLE_TEMPLATES.map((t, i) => ({
    id: uuid(),
    ...t,
    createdAt: now + i,
    updatedAt: now + i,
  }));
  templates = [...templates, ...items];
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showToast(T('toastSamplesAdded', items.length));
}

// ===== イベント登録 =====
searchInput.addEventListener('input', applyFilter);
categoryFilter.addEventListener('change', applyFilter);

$('btnNew').addEventListener('click', () => openEdit(null));

// ⚙ は開閉の両方を兼ねる。入出力画面から戻るのに一番下までスクロールしなくて済むよう、
// もう一度押したら一覧に戻す（「一覧に戻る」ボタンも残してある）
$('btnIO').addEventListener('click', () => showView(viewIO.hidden ? 'io' : 'list'));

// 別ウィンドウで開くボタンは、拡張として動いていてサイドパネル側にいるときだけ出す
if (canOpenWindow && !isPopupWindow && !isEmbedded) {
  $('btnPopout').hidden = false;
  $('btnPopout').addEventListener('click', openInWindow);
}

// サイドパネルに戻すボタンは、別ウィンドウ側でだけ出す
if (canOpenWindow && isPopupWindow && chrome.sidePanel && chrome.sidePanel.open) {
  $('btnDock').hidden = false;
  $('btnDock').addEventListener('click', returnToSidePanel);
}
$('btnCloseIO').addEventListener('click', () => showView('list'));

// 画面に出ている本文をそのままコピーする（編集中の内容もそのまま持っていける）
$('btnCopyBody').addEventListener('click', async () => {
  const body = $('editBody').value;
  if (!body.trim()) {
    showToast(T('toastBodyEmpty'), true);
    return;
  }
  const ok = await copyText(body);
  showToast(T(ok ? 'toastBodyCopied' : 'toastCopyFailed'), !ok);
});

$('btnSave').addEventListener('click', saveEdit);
$('btnBackToList').addEventListener('click', leaveEdit);
$('btnEditUndo').addEventListener('click', undoFromEdit);

$('btnRevertEdit').addEventListener('click', revertEdit);

// 触ったらすぐ「保存していない変更があります」と保存ボタンを出す。
// 変更したことに自分で気づけるようにするのが狙い
for (const id of ['editCategory', 'editTitle', 'editBody']) {
  $(id).addEventListener('input', updateEditState);
}
$('btnDelete').addEventListener('click', deleteEditing);

$('btnImport').addEventListener('click', importPasted);

// ファイル選択・ドラッグ&ドロップ
const dropZone = $('dropZone');
const fileInput = $('fileInput');

dropZone.addEventListener('click', () => fileInput.click());
dropZone.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    fileInput.click();
  }
});
fileInput.addEventListener('change', () => {
  const file = fileInput.files[0];
  fileInput.value = ''; // 同じファイルを続けて選び直せるようにする
  importFromFile(file);
});

for (const ev of ['dragenter', 'dragover']) {
  dropZone.addEventListener(ev, (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
    dropZone.classList.add('dragover');
  });
}
for (const ev of ['dragleave', 'dragend']) {
  dropZone.addEventListener(ev, (e) => {
    e.preventDefault();
    e.stopPropagation();
    dropZone.classList.remove('dragover');
  });
}
dropZone.addEventListener('drop', (e) => {
  e.preventDefault();
  e.stopPropagation();
  dropZone.classList.remove('dragover');
  const file = e.dataTransfer && e.dataTransfer.files[0];
  if (!file) return;
  importFromFile(file);
});

// 枠の外にドロップしたときにパネルがファイル表示に置き換わるのを防ぐ
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('drop', (e) => e.preventDefault());

$('btnExportCSV').addEventListener('click', () => {
  // ExcelでそのままUTF-8として開けるようにBOMを付ける（読み込み側はBOMを除去する）
  downloadFile(
    `osamukun_${dateStamp()}.csv`,
    '\uFEFF' + toDelimited(templates, COMMA, localizedHeaders()),
    'text/csv'
  );
});
$('btnExportTSV').addEventListener('click', () => {
  downloadFile(
    `osamukun_${dateStamp()}.tsv`,
    toDelimited(templates, TAB, localizedHeaders()),
    'text/tab-separated-values'
  );
});
$('btnExportJSON').addEventListener('click', () => {
  downloadFile(`osamukun_${dateStamp()}.json`, JSON.stringify(templates, null, 2), 'application/json');
});
$('btnDeleteAll').addEventListener('click', async () => {
  if (templates.length === 0) {
    showToast(T('toastNothingToDelete'), true);
    return;
  }
  if (!confirm(T('confirmDeleteAll', templates.length))) return;
  await captureUndo(T('labelDeleteAll', templates.length));
  templates = [];
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showView('list');
  showToast(T('toastDeletedAll'));
});

$('btnLoadSamples').addEventListener('click', loadSamples);
$('btnUndo').addEventListener('click', performUndo);

// ===== 初期化 =====
(async function init() {
  // 別ウィンドウが生きているならそちらに任せて閉じる。描画前に判定して画面のちらつきを避ける
  if (await handOverToExistingWindow()) return;
  // 文言を先に用意する。この後の描画も T() を通るため、順序を入れ替えないこと
  await loadPreviewMessages();
  applyI18n();
  templates = await storage.get();
  renderCategoryOptions();
  applyFilter();
  searchInput.focus();
})();
