# プライバシーポリシー / Privacy Policy

最終更新日: 2026-08-04

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

### データの削除
登録した定型文は、拡張機能の入出力画面から「全ての定型文を削除」でいつでも消去できます。Chromeから本拡張機能をアンインストールした場合も、保存されたデータは削除されます。

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

### Deleting Your Data
You can erase all saved templates at any time from the import/export screen ("Delete all templates"). Uninstalling the Extension from Chrome also removes the stored data.

### Contact
For questions about this policy, please open an issue on the GitHub repository: https://github.com/Goma-kun/osamukun
