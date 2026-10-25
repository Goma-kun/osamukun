import SwiftUI

/// 画面が共有する状態。定型文の読み書きは必ずここを通す（保存・元に戻すの控えを揃えるため）。
/// 拡張の sidepanel.js の「状態」「元に戻す」「追加・編集・削除」「インポート」に当たる
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var snapshot: Snapshot
    @Published private(set) var undo: UndoSnapshot?
    /// 管理ウィンドウの一覧の絞り込み
    @Published var query = ""
    @Published var category = ""
    /// 管理ウィンドウで開いている定型文（nil は何も選んでいない、"new" は追加中）
    @Published var selectedID: String?
    /// 画面下に出す一言（1.8 秒で消える）
    @Published var toast: Toast?

    struct Toast: Equatable { var text: String; var isError = false; var id = UUID() }

    let store: Store
    private var toastTask: Task<Void, Never>?

    init(store: Store = Store(directory: Platform.storeDirectory)) {
        self.store = store
        snapshot = store.loadSnapshot()
        undo = store.loadUndo()
    }

    var templates: [Template] { snapshot.templates }
    var categories: [String] { snapshot.categories }
    var filtered: [Template] { Search.filter(templates, query: query, category: category) }
    func template(_ id: String?) -> Template? { id.flatMap { id in templates.first { $0.id == id } } }

    static let untitled = String(localized: "（無題）")
    static func shownTitle(_ t: Template) -> String { t.title.isEmpty ? untitled : t.title }

    // MARK: - 保存

    private func persist() {
        do { try store.save(snapshot) } catch { showToast(String(localized: "保存できませんでした：\(error.localizedDescription)"), isError: true) }
    }

    func showToast(_ text: String, isError: Bool = false) {
        toast = Toast(text: text, isError: isError)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: - 元に戻す（1 段。変更を加える「前」に captureUndo を呼ぶ）

    private func captureUndo(_ label: String, isUndo: Bool = false) {
        let u = UndoSnapshot(templates: templates, label: label, isUndo: isUndo)
        undo = u
        try? store.save(u)
    }

    /// 取り消し自体もやり直せるように、いまの状態を新しい控えにしてから戻す
    @discardableResult
    func performUndo() -> Bool {
        guard let u = undo else { showToast(String(localized: "取り消せる操作がありません"), isError: true); return false }
        captureUndo(u.label, isUndo: !u.isUndo)
        snapshot.restore(u.templates)
        persist()
        showToast(u.isUndo ? String(localized: "\(u.label) をやり直しました") : String(localized: "\(u.label) を取り消しました"))
        return true
    }

    // MARK: - 追加・編集・削除

    /// 保存。`id` が nil なら追加。戻り値は保存後の定型文（前後の空白を落とした内容）
    @discardableResult
    func save(id: String?, category: String, title: String, body: String) -> Template? {
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showToast(String(localized: "概要か本文を入力してください"), isError: true)
            return nil
        }
        let shown = title.isEmpty ? Self.untitled : title
        var saved: Template
        if let id, var t = template(id) {
            captureUndo(String(localized: "「\(shown)」の編集"))
            t.category = category; t.title = title; t.body = body; t.updatedAt = Template.nowMs()
            saved = t
        } else {
            captureUndo(String(localized: "「\(shown)」の追加"))
            saved = Template(category: category, title: title, body: body)
        }
        snapshot.upsert(saved)
        persist()
        showToast(String(localized: "保存しました"))
        return saved
    }

    func delete(id: String) {
        guard let t = template(id) else { return }
        captureUndo(String(localized: "「\(Self.shownTitle(t))」の削除"))
        snapshot.remove(id: id)
        persist()
        if selectedID == id { selectedID = nil }
        showToast(String(localized: "削除しました。入出力の「元に戻す」から取り消せます"))
    }

    func deleteAll() {
        guard !templates.isEmpty else { showToast(String(localized: "削除する定型文がありません"), isError: true); return }
        captureUndo(String(localized: "全\(templates.count)件の削除"))
        snapshot.removeAll()
        persist()
        selectedID = nil
        showToast(String(localized: "全て削除しました。入出力の「元に戻す」から取り消せます"))
    }

    func loadSamples() {
        let items = Samples.templates(japanese: AppInfo.isJapanese)
        captureUndo(String(localized: "サンプル\(items.count)件の追加"))
        snapshot.importTemplates(items, replace: false)
        // 拡張はサンプルを末尾に足す（既存の定型文を上に残す）
        snapshot.restore(Array(snapshot.templates.dropFirst(items.count)) + items)
        persist()
        showToast(String(localized: "サンプル\(items.count)件を追加しました"))
    }

    // MARK: - インポート／エクスポート

    struct ImportResult { var ok: Bool; var imported: Int; var skipped: Int; var message: String }

    /// 解析済みの行を取り込む。置き換えの確認は画面側で済ませてから呼ぶ
    func importRows(_ rows: [[String]], replace: Bool) -> ImportResult {
        let r = Delimited.templates(fromRows: rows)
        return importTemplates(r.imported, skipped: r.skipped, replace: replace)
    }

    func importTemplates(_ items: [Template], skipped: Int, replace: Bool) -> ImportResult {
        if items.isEmpty {
            let msg = skipped > 0 ? String(localized: "取り込める行がありませんでした（\(skipped)行をスキップ）")
                                  : String(localized: "取り込める行がありませんでした")
            showToast(msg, isError: true)
            return ImportResult(ok: false, imported: 0, skipped: skipped, message: msg)
        }
        captureUndo(replace ? String(localized: "\(items.count)件で置き換え") : String(localized: "\(items.count)件のインポート"))
        snapshot.importTemplates(items, replace: replace)
        persist()
        let msg = skipped > 0 ? String(localized: "\(items.count)行を読み込み、\(skipped)行をスキップしました")
                              : String(localized: "\(items.count)件をインポートしました")
        showToast(msg)
        return ImportResult(ok: true, imported: items.count, skipped: skipped, message: msg)
    }

    /// ファイルの中身を取り込む。拡張子と中身から CSV/TSV/JSON を見分ける
    func importFile(name: String, data: Data, replace: Bool) -> ImportResult {
        if name.lowercased().hasSuffix(".json") {
            do {
                let items = try Delimited.templates(fromJSON: data)
                return importTemplates(items, skipped: 0, replace: replace)
            } catch {
                let msg = String(localized: "\(name) を JSON として読めませんでした")
                showToast(msg, isError: true)
                return ImportResult(ok: false, imported: 0, skipped: 0, message: msg)
            }
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            let msg = String(localized: "\(name) は UTF-8 のテキストではありませんでした")
            showToast(msg, isError: true)
            return ImportResult(ok: false, imported: 0, skipped: 0, message: msg)
        }
        let text = Delimited.stripBOM(raw)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msg = String(localized: "\(name) は空のファイルでした")
            showToast(msg, isError: true)
            return ImportResult(ok: false, imported: 0, skipped: 0, message: msg)
        }
        let d = Delimited.detectDelimiter(text, filename: name)
        var r = importRows(Delimited.parse(text, delimiter: d.delimiter), replace: replace)
        let label = d.delimiter == Delimited.tab ? String(localized: "タブ区切り") : String(localized: "カンマ区切り")
        let reason = d.reason == .ext ? String(localized: "拡張子から判定") : String(localized: "先頭行から判定")
        r.message = String(localized: "\(name)：\(label)として読み込みました（\(reason)）。\(r.message)")
        return r
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv, tsv, json
        var id: String { rawValue }
        var fileExtension: String { rawValue }
    }

    static var localizedHeaders: [String] {
        [String(localized: "カテゴリ"), String(localized: "概要"), String(localized: "本文")]
    }

    func exportData(_ format: ExportFormat) -> Data {
        switch format {
        case .csv:
            // Excel でそのまま UTF-8 として開けるように BOM を付ける（読み込み側は BOM を除く）
            return Data("\u{FEFF}".utf8) + Data(Delimited.serialize(templates, delimiter: Delimited.comma, headers: Self.localizedHeaders).utf8)
        case .tsv:
            return Data(Delimited.serialize(templates, delimiter: Delimited.tab, headers: Self.localizedHeaders).utf8)
        case .json:
            return Delimited.json(templates)
        }
    }

    static func exportFilename(_ format: ExportFormat) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "osamukun_\(f.string(from: Date())).\(format.fileExtension)"
    }

    static func formatUndoTime(_ at: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: at / 1000))
    }
}
