# おさむくん

定型文（テンプレート・スニペット）を登録・検索して、ワンクリックでコピーできるChrome拡張機能です。
メールの定型文管理を想定していますが、よく使う文章なら何でも登録できます。

*English speakers: see [English](#english) at the bottom.*

## 特徴

- **サイドパネル型**：ブラウザの横に常駐。ツールバーのアイコンをクリックで開閉
- **入出力画面の開閉**：ヘッダーの ⚙ を押すと入出力画面へ、もう一度押すと一覧に戻ります
- **別ウィンドウ表示**：ヘッダーの ⧉ ボタンで独立したウィンドウに切り替わります。位置もサイズも自由で、Chrome以外のアプリに貼り付けるときも手前に置いておけます。別ウィンドウの ⇥ ボタンでサイドパネルに戻せます。二重に表示されることはありません
- **インクリメンタル検索**：タイトル・本文・カテゴリを対象に、入力と同時に絞り込み
- **ワンクリックコピー**：項目をクリックすると本文がクリップボードへ
- **全文の確認**：項目の「全文」ボタンで内容を最後まで読めます。その画面から編集・保存・コピーがそのままできます。読むだけのときは保存ボタンが出ないので、うっかり書き換えてもすぐ気づけます
- **キーボード操作**：検索ボックスに自動フォーカス。↑↓で選択、Enterでコピー、Escでクリア
- **ショートカット起動**：好きなキーを割り当ててサイドパネルを開けます（既定キーはあえて設けていません）
- **貼り付けインポート**：スプレッドシートの3列（カテゴリ／概要／本文）を範囲コピーして貼り付けるだけ
- **ファイルインポート**：CSV・TSVファイルの読み込みに対応。ファイル選択とドラッグ&ドロップの両方が使えます
- **エクスポート**：CSV・TSV・JSONの3形式でバックアップ
- **元に戻す**：保存・追加・削除・インポートを、直前のひとつだけ取り消せます。保存した直後はその場に「元に戻す」が出ますし、あとからでも ⚙ の画面から取り消せます
- **完全オフライン**：外部通信は一切ありません。データは `chrome.storage.local` にのみ保存されます
- **日本語・英語のUI**：Chromeの表示言語に合わせて切り替わります（`_locales` による i18n）

## 権限

`sidePanel` と `storage` のみ。host_permissions・content script・remote codeは使用していません。
ファイルの読み込みは `FileReader` で行うため、ファイル関連の権限も不要です。

## キーボードショートカット

サイドパネルは、ツールバーのアイコンをクリックすれば開きます。
キーボードから開きたい場合は `chrome://extensions/shortcuts` を開いて、おさむくんの「おさむくんのサイドパネルを開く」に好きなキーを割り当ててください。

**既定のキーはあえて設定していません。** Chromeのショートカットは先着優先で、他の拡張機能が同じ組み合わせを先に取っていると、こちらは警告もなく未割り当てになります。何を既定にしても誰かの環境では確実にぶつかるので、空いているキーをご自身で選べるようにしています。

## インポートの形式

カテゴリ／概要／本文の3列です。1行目が「カテゴリ」または「category」で始まる場合はヘッダー行として読み飛ばします。

- 区切り文字は自動で判定します。拡張子が `.csv` / `.tsv` ならそれを優先し、`.txt` などは先頭行のカンマとタブの数で決めます
- 文字コードはUTF-8です。BOM付き（Excelが書き出すCSVによくある形）でも読み込めます
- 改行コードはLF・CRLFのどちらでも構いません
- カンマ・タブ・改行・引用符を含むセルは、ダブルクォートで囲んでください（`""` で引用符自体をエスケープ）
- 3列に収まらない行は読み飛ばし、件数を画面に表示します

CSVエクスポートはExcelでそのまま開けるようBOM付きで書き出します。読み込み側はBOMを取り除くので、書き出したファイルはそのまま読み戻せます。

## インストール（開発版）

1. このリポジトリをダウンロード
2. Chromeで `chrome://extensions` を開く
3. 右上の「デベロッパーモード」をオン
4. 「パッケージ化されていない拡張機能を読み込む」で `extension` フォルダを選択

## バックアップについて

データは各自のブラウザの `chrome.storage.local` にのみ保存されます。同期はしないので、誰かが消しても他の人には影響しませんが、**復旧も各自の端末の中だけ**です。

「元に戻す」は直前のひとつを取り消すための保険であって、バックアップではありません。大事なデータや、複数人に配って使う場合は、⚙の**エクスポートでCSVを保存しておく**ことをおすすめします。そのCSVはそのまま読み込み直せます。

## テスト

`sidepanel.js` のCSV/TSVパーサー部分を切り出して、ラウンドトリップ整合と区切り文字判定を検証します。

```bash
node test/parser_test.mjs
```

拡張機能の配布物には含まれません（`extension/` の外に置いています）。

## データモデル

```json
{ "id": "...", "category": "依頼", "title": "資料送付のお願い", "body": "...", "createdAt": 0, "updatedAt": 0 }
```

## 変更履歴

### v1.8.0（2026-08-10）

- **画面を英語に対応しました。** Chromeの表示言語が日本語なら日本語、それ以外なら英語で表示されます（`_locales/ja`・`_locales/en`）
- サンプル定型文も画面の言語に合わせて出し分けます。英語のときは英語のビジネス定型文10件を読み込みます
- CSV／TSVを書き出すときのヘッダー行（カテゴリ／概要／本文）も画面の言語に合わせます。どちらの言語で書き出しても、そのまま読み戻せます
- Chrome ウェブストアの掲載情報も日英2言語になりました
- **⚙ をもう一度押すと一覧に戻る**ようにしました。入出力画面から戻るのに一番下までスクロールしなくて済みます（「一覧に戻る」ボタンもそのまま残してあります）

### v1.7.1（2026-08-04）

- 拡張機能の更新・再読み込みやブラウザの起動後に、閉じられた別ウィンドウの情報が残らないようにしました

### v1.7.0（2026-08-04）

- 全文の画面で、**何か書き換えたときだけ保存ボタンが出る**ようにしました。保存が現れること自体が「変えてしまった」という合図になります
- 書き換えると「保存していない変更があります」と表示され、**変更を取り消す**で開いたときの内容に戻せます
- 保存直後の**元に戻す**（保存そのものの取り消し）とは役割が違うため、名前を分けています

### v1.6.1（2026-08-04）

- 保存した直後の画面を「一覧に戻る」と「元に戻す」だけにしました。保存したばかりの画面に保存ボタンと削除ボタンが残っていると分かりにくいためです。本文などを書き換え始めると、保存ボタンと削除ボタンが戻ります
- 「元に戻す」ボタンが2行に折り返すことがあったのを修正しました

### v1.6.0（2026-08-04）

- 保存しても一覧に戻らず、そのまま編集画面に留まるようにしました。続けて直せます
- 保存直後に**その場で「元に戻す」**が出るようにしました。⚙まで行かなくても、押し間違いにすぐ気づけます
- 「キャンセル」を「一覧に戻る」に変更しました。保存していない変更があるときは確認します

### v1.5.0（2026-08-04）

- 「元に戻す」を追加しました。⚙の画面から、直前の操作をひとつだけ取り消せます
  - 対象は保存・追加・削除・全件削除・インポート（追記／置き換え）・サンプル読み込み
  - 何を取り消すのかをボタンの下に表示します（例：`取り消せる操作：「資料送付のお願い」の編集（08/04 10:33）`）
  - もう一度押すと、取り消した操作をやり直せます
  - サイドパネルを閉じても残ります

### v1.4.0（2026-08-04）

- 一覧の項目にあった編集アイコン（✎）を「全文」ボタンに変更しました。一覧では本文が2行までしか出ないため、中身を最後まで読みたいときの入口だと分かるようにしています
- 開いた画面に「本文をコピー」ボタンを追加しました。読んでから戻ってコピーし直す必要がなくなります
- 画面の見出しを「定型文を編集」から「定型文の内容」に変更しました（読むために開くことも多いため）

### v1.3.1（2026-08-04）

- Chromeのウィンドウを複数開いているとき、サイドパネルに戻すと別のウィンドウに開いてしまう問題を修正しました。別ウィンドウを開いたときのウィンドウを覚えておき、そこに戻します（そのウィンドウが閉じられている場合は残っているウィンドウに開きます）

### v1.3.0（2026-08-04）

- 別ウィンドウのヘッダーに ⇥ ボタンを追加。押すとサイドパネルに戻ります（別ウィンドウは閉じます）
- これで サイドパネル ⇄ 別ウィンドウ を両方向に行き来できるようになりました

### v1.2.0（2026-08-04）

- ヘッダーに ⧉ ボタンを追加。押すと独立したウィンドウに切り替わります（位置・サイズを自由に変えられます）
- 同じものが2つ並ばないようにしました。⧉ で切り替えるとサイドパネルは閉じ、別ウィンドウを開いている間はツールバーのアイコンを押してもそのウィンドウが前面に出ます
- サイドパネルと別ウィンドウを同時に開いても、片方の追加・編集・削除がもう片方に反映されるようになりました
- 権限は `sidePanel` / `storage` のまま増えていません（`chrome.windows` は権限宣言なしで使えます）

### v1.1.0（2026-08-04）

- CSV / TSVファイルのインポートを追加（ファイル選択＋ドラッグ&ドロップ、区切り文字は自動判定）
- CSVエクスポートを追加。CSV・TSV・JSONの3形式になりました
- BOM付きUTF-8とCRLF改行に対応。引用符で囲まれたセル内のCRLFもLFに揃えます
- 3列に合わない行はスキップし、読み込み件数とスキップ件数を表示するようにしました
- 追記／置き換えの選択が、貼り付け・ファイル読み込みの両方に効くようになりました
- 空状態の画面に、スプレッドシートから取り込める旨の案内を追加
- キーボードショートカットでサイドパネルを開けるようにしました（`chrome://extensions/shortcuts` で任意のキーを割り当て）

### v1.0.0（2026-07-16）

- 初回リリース。検索・カテゴリフィルタ・クリックコピー・追加編集削除・TSV貼り付けインポート・TSV/JSONエクスポート

## ライセンス

MIT

---

## English

**Osamukun** is a Chrome extension for the text you write over and over: save it, search it, copy it with one click. It was built for email templates, but anything you retype works — greetings, status formats, support replies, prompts for an AI chat.

### What it does

- **Lives in the side panel.** Click the toolbar icon to open and close it
- **Or in a window of its own.** The ⧉ button in the header moves it to a separate window you can size and place anywhere, so it stays in front of apps outside Chrome. ⇥ moves it back. It never shows up in two places at once
- **Search as you type**, across title, body and category
- **Click to copy.** The body goes straight to your clipboard
- **"Full text"** opens the whole entry, where you can read, edit, save and copy it. When you only opened it to read, no save button appears — so an accidental edit is visible before it becomes permanent
- **Keyboard only, if you like.** The search box is focused when it opens; ↑↓ to move, Enter to copy, Esc to clear
- **A shortcut key, if you want one.** No default is set (see below)
- **Paste from a spreadsheet.** Select three columns — category, title, body — copy, paste
- **Read CSV and TSV files**, by choosing a file or dropping it in
- **Export** as CSV, TSV or JSON, and read what you exported straight back in
- **Undo.** Saving, adding, deleting and importing can each be taken back — the last one is always kept
- **Fully offline.** No network code at all. Your data lives in `chrome.storage.local` on your own machine
- **English and Japanese**, following your Chrome language setting

### Permissions

`sidePanel` and `storage`, and nothing else. No host permissions, no content scripts, no remote code. Files are read with `FileReader`, so no file permission is needed either.

Osamukun copies to your clipboard rather than typing into the field for you. That is deliberate: inserting text into a page requires permission to read that page, and this extension does not ask for it.

### Keyboard shortcut

Clicking the toolbar icon opens the side panel. To open it from the keyboard, go to `chrome://extensions/shortcuts` and assign a key to "Open the Osamukun side panel".

**No default key is set, on purpose.** Chrome hands shortcuts out first-come-first-served, and an extension that loses gets no warning — the key is simply unassigned. Whatever default we picked would silently collide in someone's browser, so you choose one that is free.

### Import format

Three columns: category, title, body. A first row starting with `category` (or `カテゴリ`) is treated as a header and skipped.

- The delimiter is detected for you. A `.csv` or `.tsv` extension decides it; otherwise the commas and tabs in the first line are counted
- Files are read as UTF-8. A BOM (as Excel writes) is fine
- LF and CRLF line endings both work
- Wrap a cell in double quotes if it contains a comma, tab, newline or quote (`""` escapes a quote itself)
- Rows that do not fit into three columns are skipped, and the count is shown on screen

CSV export includes a BOM so Excel opens it correctly; the import side strips it, so anything you export reads straight back in.

### Install (development build)

1. Download this repository
2. Open `chrome://extensions` in Chrome
3. Turn on "Developer mode" (top right)
4. Choose "Load unpacked" and select the `extension` folder

### A note on backups

Your data lives only in `chrome.storage.local` in your own browser. It is never synced, so no one else can lose it for you — but no one else can recover it for you either.

Undo is there to catch the last mistake, not to be a backup. For anything you would not want to retype, export a CSV from the ⚙ screen. That CSV reads straight back in.

### Tests

The CSV/TSV parser inside `sidepanel.js` is extracted and checked for round-trip integrity and delimiter detection:

```bash
node test/parser_test.mjs
```

It is not part of what ships (it lives outside `extension/`).

### License

MIT
