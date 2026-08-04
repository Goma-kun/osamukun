'use strict';

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
}

// ===== 別ウィンドウ表示 =====
// サイドパネルはChromeの仕様で枠から切り離せないため、独立したウィンドウで開く手段を用意する。
// chrome.windows は権限宣言なしで使えるので、権限は sidePanel / storage のまま増えない。
// （既存ウィンドウの再利用も、URL検索ではなくウィンドウIDの記憶で済ませて tabs 権限を避けている）
const WINDOW_WIDTH = 400;
const WINDOW_HEIGHT = 700;
const POPUP_ID_KEY = 'popupWindowId';
const isPopupWindow = new URLSearchParams(location.search).get('view') === 'window';
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
  // 元のウィンドウの右端に沿えて出す。座標が取れない場合はChromeの既定位置に任せる
  try {
    const base = await chrome.windows.getLastFocused();
    if (typeof base.left === 'number' && typeof base.width === 'number') {
      options.left = Math.max(0, base.left + base.width - WINDOW_WIDTH - 20);
      options.top = Math.max(0, (base.top || 0) + 20);
    }
  } catch {
    // 位置指定なしで開く
  }

  try {
    const created = await chrome.windows.create(options);
    // 閉じる前にIDを確実に保存する（保存前にパネルを閉じると次回の再利用ができなくなる）
    await chrome.storage.local.set({ [POPUP_ID_KEY]: created.id });
    return true;
  } catch {
    showToast('別ウィンドウを開けませんでした', true);
    return false;
  }
}

async function openInWindow() {
  // 同じものがサイドパネルと別ウィンドウに2つ並ぶと分かりにくいので、
  // 別ウィンドウを開けたらサイドパネルのほうは閉じる
  if (await ensureWindow()) window.close();
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
    if (area !== 'local' || !changes.templates) return;
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
  categoryFilter.innerHTML = '<option value="">すべてのカテゴリ</option>';
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
    title.textContent = t.title || '（無題）';
    top.appendChild(title);
    li.appendChild(top);

    const preview = document.createElement('div');
    preview.className = 'item-preview';
    // 空行で行数を消費しないよう、プレビューでは改行をスペースに畳む
    preview.textContent = t.body.replace(/\s*\n\s*/g, ' ').trim();
    li.appendChild(preview);

    const editBtn = document.createElement('button');
    editBtn.className = 'item-edit-btn';
    editBtn.textContent = '✎';
    editBtn.title = '編集';
    editBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      openEdit(t.id);
    });
    li.appendChild(editBtn);

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
        ? `${templates.length}件`
        : `${filtered.length}件 / 全${templates.length}件`;
}

async function copyTemplate(t, element) {
  const ok = await copyText(t.body);
  if (ok) {
    showToast(`「${t.title}」をコピーしました`);
    if (element) {
      element.classList.add('copied');
      setTimeout(() => element.classList.remove('copied'), 700);
    }
  } else {
    showToast('コピーに失敗しました', true);
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
  $('editHeading').textContent = t ? '定型文を編集' : '定型文を追加';
  $('editCategory').value = t ? t.category : categoryFilter.value || '';
  $('editTitle').value = t ? t.title : '';
  $('editBody').value = t ? t.body : '';
  $('btnDelete').hidden = !t;
  showView('edit');
  $('editTitle').focus();
}

async function saveEdit() {
  const category = $('editCategory').value.trim();
  const title = $('editTitle').value.trim();
  const body = $('editBody').value;
  if (!title && !body.trim()) {
    showToast('概要か本文を入力してください', true);
    return;
  }
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
    templates.unshift({ id: uuid(), category, title, body, createdAt: now, updatedAt: now });
  }
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showView('list');
  showToast('保存しました');
}

async function deleteEditing() {
  if (!editingId) return;
  const t = templates.find((x) => x.id === editingId);
  if (!confirm(`「${t ? t.title : ''}」を削除しますか？`)) return;
  templates = templates.filter((x) => x.id !== editingId);
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showView('list');
  showToast('削除しました');
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

// 区切り文字の判定。拡張子で分かるならそれを使い、分からなければ先頭行のタブとカンマを数える
function detectDelimiter(text, filename = '') {
  const ext = filename.toLowerCase().match(/\.([a-z0-9]+)$/);
  if (ext && ext[1] === 'csv') return { delimiter: COMMA, reason: '拡張子から判定' };
  if (ext && ext[1] === 'tsv') return { delimiter: TAB, reason: '拡張子から判定' };

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
  return { delimiter: tabs >= commas ? TAB : COMMA, reason: '先頭行から判定' };
}

function delimiterLabel(delimiter) {
  return delimiter === TAB ? 'タブ区切り' : 'カンマ区切り';
}

function delimitedField(s, delimiter) {
  return s.includes(delimiter) || /["\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function toDelimited(items, delimiter) {
  const lines = [['カテゴリ', '概要', '本文'].map((h) => delimitedField(h, delimiter)).join(delimiter)];
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

// 貼り付け・ファイル読み込みの共通処理。追記／置き換えの選択を適用して保存する
async function runImport(rows, { backToList }) {
  const { imported, skipped } = rowsToTemplates(rows);
  if (imported.length === 0) {
    const msg =
      skipped > 0 ? `取り込める行がありませんでした（${skipped}行をスキップ）` : '取り込める行がありませんでした';
    showToast(msg, true);
    return { ok: false, imported: 0, skipped, message: msg };
  }

  const mode = document.querySelector('input[name="importMode"]:checked').value;
  if (mode === 'replace') {
    if (!confirm(`既存の${templates.length}件を削除して、${imported.length}件で置き換えます。よろしいですか？`)) {
      return { ok: false, cancelled: true, imported: 0, skipped, message: 'インポートを中止しました' };
    }
    templates = imported;
  } else {
    templates = [...imported, ...templates];
  }
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  if (backToList) showView('list');

  const message =
    skipped > 0
      ? `${imported.length}行を読み込み、${skipped}行をスキップしました`
      : `${imported.length}件をインポートしました`;
  showToast(message);
  return { ok: true, imported: imported.length, skipped, message };
}

// 貼り付けインポートはスプレッドシートの範囲コピーが前提なので、区切り文字はタブ固定
async function importPasted() {
  const text = $('importText').value;
  if (!text.trim()) {
    showToast('インポートするデータを貼り付けてください', true);
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
  setFileStatus(`${file.name} を読み込んでいます…`);

  let text;
  try {
    text = stripBOM(await readFileAsText(file));
  } catch {
    setFileStatus(`${file.name} を読み込めませんでした。`, true);
    showToast('ファイルを読み込めませんでした', true);
    return;
  }

  if (!text.trim()) {
    setFileStatus(`${file.name} は空のファイルでした。`, true);
    showToast('ファイルが空です', true);
    return;
  }

  const { delimiter, reason } = detectDelimiter(text, file.name);
  const label = delimiterLabel(delimiter);
  setFileStatus(`${file.name}：${label}として読み込みます（${reason}）`);

  const result = await runImport(parseDelimited(text, delimiter), { backToList: false });
  setFileStatus(`${file.name}：${label}として読み込みました。${result.message}`, !result.ok);
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
const SAMPLE_TEMPLATES = [
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

async function loadSamples() {
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
  showToast(`サンプル${items.length}件を追加しました`);
}

// ===== イベント登録 =====
searchInput.addEventListener('input', applyFilter);
categoryFilter.addEventListener('change', applyFilter);

$('btnNew').addEventListener('click', () => openEdit(null));
$('btnIO').addEventListener('click', () => showView('io'));

// 別ウィンドウで開くボタンは、拡張として動いていてサイドパネル側にいるときだけ出す
if (canOpenWindow && !isPopupWindow) {
  $('btnPopout').hidden = false;
  $('btnPopout').addEventListener('click', openInWindow);
}
$('btnCloseIO').addEventListener('click', () => showView('list'));

$('btnSave').addEventListener('click', saveEdit);
$('btnCancelEdit').addEventListener('click', () => showView('list'));
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
  downloadFile(`osamukun_${dateStamp()}.csv`, '\uFEFF' + toDelimited(templates, COMMA), 'text/csv');
});
$('btnExportTSV').addEventListener('click', () => {
  downloadFile(`osamukun_${dateStamp()}.tsv`, toDelimited(templates, TAB), 'text/tab-separated-values');
});
$('btnExportJSON').addEventListener('click', () => {
  downloadFile(`osamukun_${dateStamp()}.json`, JSON.stringify(templates, null, 2), 'application/json');
});
$('btnDeleteAll').addEventListener('click', async () => {
  if (templates.length === 0) {
    showToast('削除する定型文がありません', true);
    return;
  }
  if (!confirm(`全${templates.length}件の定型文を削除します。よろしいですか？`)) return;
  templates = [];
  await storage.set(templates);
  renderCategoryOptions();
  applyFilter();
  showView('list');
  showToast('全て削除しました');
});

$('btnLoadSamples').addEventListener('click', loadSamples);

// ===== 初期化 =====
(async function init() {
  templates = await storage.get();
  renderCategoryOptions();
  applyFilter();
  searchInput.focus();
})();
