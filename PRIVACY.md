# プライバシーポリシー / Privacy Policy

最終更新日 / Last updated: 2026-10-26

このポリシーは、**Chrome 拡張機能版**と **Mac / iPhone アプリ版**に適用されます。
This policy covers the **Chrome extension** and the **Mac / iPhone app**.

## 日本語

おさむくん（以下「本拡張機能」）は、利用者のプライバシーを尊重します。

### 収集する情報
本拡張機能は、利用者の個人情報・閲覧履歴・入力内容などを**一切収集しません**。

### データの送信
本拡張機能は、いかなるデータも外部サーバーへ**送信しません**。通信を行うコードそのものを含んでいません。開発者や第三者がデータを受け取ることはありません。

### 登録した定型文の扱い
- 登録した定型文（カテゴリ・概要・本文）は、利用者自身の端末内の `chrome.storage.local` にのみ保存されます。
- 同期は行いません。他の端末や他の利用者と共有されることはありません。
- 定型文の内容がネットワークを経由して外部に送られることはありません。
- 読み込んだCSV／TSVファイルは、利用者の端末内で解析されるだけです。アップロードは行いません。
- クリップボードへのコピーは、利用者がその操作を行ったときにのみ発生します。

### 権限について
本拡張機能が要求する権限は `sidePanel` と `storage` の2つだけです。

- **sidePanel**: 定型文の一覧・検索画面をブラウザのサイドパネルに表示するために使用します。
- **storage**: 登録した定型文を利用者の端末内に保存するために使用します。

閲覧中のページを読み取る権限（host_permissions）、ページにコードを差し込む仕組み（content script）、外部から取得したコードの実行（remote code）は、いずれも使用していません。

### Mac / iPhone アプリ版について

アプリ版も、集めない・送らないという方針は拡張機能版と同じです。

- 登録した定型文は、お使いの端末の中（アプリ専用の保存領域）にのみ保存されます。開発者が運用するサーバーはありません
- アクセス解析・トラッキング・広告は行いません。アカウント登録やログインは不要です
- **直接貼り付け（Mac 版）**：選んだ本文を直前に使っていたアプリへ貼り付けるために、macOS の「アクセシビリティ」の許可をお願いすることがあります。この許可は、クリップボードに入れた本文を ⌘V のキー操作で貼り付けるためだけに使います。画面の内容や他のアプリの入力を読み取ることはありません。許可しなくても、クリップボードにコピーするところまでは使えます
- **ファイルの読み込み／書き出し**：CSV／TSV／JSON ファイルは、あなたが選んだものだけを読み、アプリの外には送りません
- 拡張機能版とアプリ版の間で、データが自動的に共有されることはありません（書き出したファイルを読み込む形で移せます）

### データの削除
登録した定型文は、拡張機能・アプリの入出力画面から「全ての定型文を削除」でいつでも消去できます。Chromeから本拡張機能をアンインストールした場合、またはアプリを削除した場合も、保存されたデータは削除されます。

### お問い合わせ
本ポリシーに関するご質問は、GitHubリポジトリ（https://github.com/Goma-kun/osamukun）のIssueよりご連絡ください。

---

## English

Osamukun ("the Extension") respects your privacy.

### Information We Collect
The Extension does **not** collect any personal information, browsing history, or input data.

### Data Transmission
The Extension does **not** transmit any data to any external server. It contains no networking code at all. Neither the developer nor any third party receives any data.

### Your Saved Templates
- Templates you save (category, title, body) are stored only in `chrome.storage.local` on your own device.
- No synchronization is performed. Nothing is shared with other devices or other users.
- Template contents are never sent anywhere over the network.
- CSV/TSV files you import are parsed locally on your device. Nothing is uploaded.
- Copying to the clipboard happens only when you perform that action.

### Permissions
The Extension requests only two permissions: `sidePanel` and `storage`.

- **sidePanel**: to display the template list and search UI in the browser side panel.
- **storage**: to save your templates on your own device.

The Extension does not use host permissions, content scripts, or remote code.

### Mac / iPhone App

The app follows the same rule as the extension: nothing is collected, nothing is sent.

- Your templates are stored only on your device, in the app's own storage. There is no server run by the developer
- No analytics, tracking or advertising. No account or sign-in is required
- **Direct paste (Mac)**: to paste the chosen text into the app you were using, Osamukun may ask for macOS "Accessibility" permission. It is used only to send the ⌘V keystroke after the text is placed on the clipboard. Osamukun does not read your screen or what you type in other apps. Without the permission, it still copies to the clipboard
- **Import / export**: only the CSV, TSV or JSON file you choose is read, and it never leaves the app
- Data is not shared automatically between the extension and the app (you can move it by exporting and importing a file)

### Deleting Your Data
You can erase all saved templates at any time from the import/export screen of the extension or the app ("Delete all templates"). Uninstalling the Extension from Chrome, or deleting the app, also removes the stored data.

### Contact
For questions about this policy, please open an issue on the GitHub repository: https://github.com/Goma-kun/osamukun
