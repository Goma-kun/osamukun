# おさむくん Mac / iPhone（アプリ版）

Chrome 拡張機能のおさむくんを、ブラウザの外でも使えるようにしたものです。
**Mac 版が先**で、iPhone 版はこのあと同じ土台の上に作ります。

## Mac 版でできること

- メニューバーに常駐します。Dock には出ません
- **呼び出しキー（既定は ⌃⇧Space）** を押すと、どのアプリを使っていても検索パネルが開きます
- 検索して ↩ を押すと、**直前に使っていたアプリへそのまま貼り付け**ます（アクセシビリティの許可が要ります。許可が無いときはクリップボードにコピーするところまで行い、⌘V は自分で押します）。⌘↩ はコピーだけ
- 定型文の追加・編集・削除、CSV／TSV／JSON の読み書き、1 段の「元に戻す」は拡張機能と同じです。拡張機能から書き出したファイルはそのまま読めます
- 日本語と英語に対応しています（OS の言語に従います）
- データは Mac の中（サンドボックスの Application Support）に JSON で保存します。外部通信はありません

## 中身

| | |
|---|---|
| `Sources/OsamukunCore/` | 画面を持たない部分。定型文の形（`Model.swift`）・CSV/TSV の読み書き（`Delimited.swift`、拡張の `sidepanel.js` と 1 対 1）・検索・元に戻す・保存・サンプル。iPhone 版と iCloud で揃えるときの混ぜ方（`Merge`）もここ |
| `Sources/ok-probe/` | JS 版と答えを突き合わせるための入口。JSON を受けて JSON を返すだけ。アプリからは使わない |
| `Tests/OsamukunCoreTests/` | Swift 側のテスト（拡張の `test/parser_test.mjs` と同じ場面＋保存・混ぜ方） |
| `App/` | SwiftUI の画面。`Mac/` にメニューバー・検索パネル・ホットキー・貼り付け（macOS だけ） |
| `Osamukun.xcodeproj` | ターゲットは `Osamukun`（iPhone）と `Osamukun (Mac)` |

## 確かめかた

```
swift build --package-path ios
swift test --package-path ios          # Swift 側だけのテスト
node test/parity_test.mjs              # ← 拡張の JS と Swift に同じ入力を食わせて 1 件ずつ比べる
```

`parity_test.mjs` は、乱数で作った壊れ気味の CSV/TSV を 400 件ほど両方に読ませて、
行の切り方・区切り文字の判定・取り込み結果・書き戻しを比べます。
**`sidepanel.js` のパーサーを直したら、`Delimited.swift` も直して、必ずこれを走らせてください。**
片方だけ直すと、拡張とアプリで読める行が食い違います。

## Mac 版のビルドと入れ替え

```
cd ios
xcodebuild -project Osamukun.xcodeproj -scheme "Osamukun (Mac)" -configuration Release \
  -derivedDataPath .build-mac-release -allowProvisioningUpdates build
osascript -e 'tell application id "jp.nishira.osamukun" to quit'
ditto .build-mac-release/Build/Products/Release/Osamukun.app /Applications/Osamukun.app
open /Applications/Osamukun.app
```

## 設計のメモ

- 検索パネルは `NSPanel` の `.nonactivatingPanel`。文字を打っていても前面のアプリが変わらないので、↩ でそこへ貼り付けられます（Spotlight と同じ仕組み）
- 貼り付けは「クリップボードに入れて ⌘V のキー操作を送る」だけです。画面の内容は読みません。キー操作を送るのにアクセシビリティの許可が要ります。案内も判定も同じ「アクセシビリティ」を見ています
- 呼び出しキーは Carbon の `RegisterEventHotKey`。サンドボックスの中で動き、許可も要りません
- 保存ファイルには消した定型文の id と時刻（`deleted`）も残します。足し合わせだけの同期は削除を伝えられないため、iPhone 版との同期に備えたものです（Mac 版 1.0 では同期しません）
