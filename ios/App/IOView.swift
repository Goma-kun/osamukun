import SwiftUI
import UniformTypeIdentifiers

/// インポート／エクスポート／元に戻す／全削除。拡張の ⚙ 画面と同じ並び
struct IOView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var replace = false
    @State private var pasted = ""
    @State private var fileStatus: (text: String, isError: Bool)?
    @State private var showImporter = false
    @State private var exportFormat: AppModel.ExportFormat?
    @State private var confirmReplace: (() -> Void)?
    @State private var showConfirmReplace = false
    @State private var confirmDeleteAll = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("インポート／エクスポート").font(.system(size: 15, weight: .bold))
                Spacer()
                Button(String(localized: "閉じる")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    importSection
                    Divider()
                    exportSection
                    Divider()
                    undoSection
                    Divider()
                    dangerSection
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 640)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { ToastView(toast: model.toast) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .json, .text]) { result in
            if case .success(let url) = result { importURL(url) }
        }
        .fileExporter(isPresented: Binding(get: { exportFormat != nil }, set: { if !$0 { exportFormat = nil } }),
                      document: ExportDocument(data: exportFormat.map { model.exportData($0) } ?? Data(), type: exportFormat?.utType ?? .plainText),
                      contentType: exportFormat?.utType ?? .plainText,
                      defaultFilename: exportFormat.map(AppModel.exportFilename)) { result in
            if case .success = result { model.showToast(String(localized: "保存しました")) }
        }
        .confirmationDialog(String(localized: "既存の\(model.templates.count)件を削除して置き換えます。よろしいですか？"),
                            isPresented: $showConfirmReplace, titleVisibility: .visible) {
            Button(String(localized: "置き換える"), role: .destructive) { confirmReplace?() }
        }
        .confirmationDialog(String(localized: "全\(model.templates.count)件の定型文を削除します。よろしいですか？"),
                            isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button(String(localized: "全て削除"), role: .destructive) { model.deleteAll() }
        }
    }

    // MARK: - インポート

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("インポート").font(.system(size: 14, weight: .bold))
            hint("取り込む列は「カテゴリ／概要／本文」の3列です。下の設定は貼り付け・ファイル読み込みの両方に適用されます。")
            Picker("", selection: $replace) {
                Text("追記する").tag(false)
                Text("全て置き換える").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)

            Text("スプレッドシートから貼り付け").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
            hint("スプレッドシートで3列を範囲コピーして、下に貼り付けてください。")
            TextEditor(text: $pasted)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
            Button(String(localized: "貼り付けた内容をインポート")) { importPasted() }
                .buttonStyle(.borderedProminent)

            Text("ファイルから読み込む").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
            hint("CSV・TSV に対応しています。区切り文字（カンマ／タブ）は自動で判定します。Chrome 拡張版おさむくんの JSON も読めます。文字コードは UTF-8 で保存してください。")
            dropZone
            if let fileStatus {
                Text(fileStatus.text).font(.system(size: 12))
                    .foregroundStyle(fileStatus.isError ? Theme.danger : Theme.muted)
                    .textSelection(.enabled)
            }
        }
    }

    private var dropZone: some View {
        Button { showImporter = true } label: {
            VStack(spacing: 4) {
                Text("ここにファイルをドロップ").font(.system(size: 13, weight: .semibold))
                Text("またはクリックしてファイルを選択（.csv / .tsv / .txt / .json）").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(dropTargeted ? Theme.selected : Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(dropTargeted ? Theme.tint : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                if let u = item as? URL { url = u }
                guard let url else { return }
                Task { @MainActor in importURL(url) }
            }
            return true
        }
    }

    private func importPasted() {
        let text = pasted
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.showToast(String(localized: "インポートするデータを貼り付けてください"), isError: true); return
        }
        // 貼り付けはスプレッドシートの範囲コピーが前提なので、区切り文字はタブ固定（拡張と同じ）
        let rows = Delimited.parse(Delimited.stripBOM(text), delimiter: Delimited.tab)
        withReplaceConfirm {
            if model.importRows(rows, replace: replace).ok { pasted = "" }
        }
    }

    private func importURL(_ url: URL) {
        let name = url.lastPathComponent
        fileStatus = (String(localized: "\(name) を読み込んでいます…"), false)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            fileStatus = (String(localized: "\(name) を読み込めませんでした。"), true)
            model.showToast(String(localized: "ファイルを読み込めませんでした"), isError: true)
            return
        }
        withReplaceConfirm {
            let r = model.importFile(name: name, data: data, replace: replace)
            fileStatus = (r.message, !r.ok)
        }
    }

    /// 「全て置き換える」のときだけ確認を挟む（既存が空なら聞かない）
    private func withReplaceConfirm(_ run: @escaping () -> Void) {
        if replace && !model.templates.isEmpty {
            confirmReplace = run
            showConfirmReplace = true
        } else {
            run()
        }
    }

    // MARK: - エクスポート

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("エクスポート").font(.system(size: 14, weight: .bold))
            hint("登録済みの定型文をファイルとして保存します。CSV・TSV は読み込みにそのまま使えますし、Chrome 拡張版おさむくんでも読めます。")
            HStack {
                Button(String(localized: "CSVで保存")) { exportFormat = .csv }
                Button(String(localized: "TSVで保存")) { exportFormat = .tsv }
                Button(String(localized: "JSONで保存")) { exportFormat = .json }
            }
            .buttonStyle(.bordered)
            .disabled(model.templates.isEmpty)
        }
    }

    // MARK: - 元に戻す

    private var undoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("元に戻す").font(.system(size: 14, weight: .bold))
            hint("直前の操作をひとつだけ取り消せます。保存・追加・削除・インポートが対象です。もう一度押すと取り消した操作をやり直せます。")
            if let u = model.undo {
                Button(u.isUndo ? String(localized: "取り消した操作をやり直す") : String(localized: "直前の操作を取り消す")) {
                    model.performUndo()
                }
                .buttonStyle(.bordered)
                let when = AppModel.formatUndoTime(u.at)
                Text(u.isUndo ? String(localized: "やり直せる操作：\(u.label)（\(when)）") : String(localized: "取り消せる操作：\(u.label)（\(when)）"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Text("取り消せる操作はありません。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("データの削除").font(.system(size: 14, weight: .bold))
            Button(String(localized: "全ての定型文を削除"), role: .destructive) { confirmDeleteAll = true }
                .buttonStyle(.bordered).foregroundStyle(Theme.danger)
        }
    }

    private func hint(_ s: LocalizedStringKey) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

extension AppModel.ExportFormat {
    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .tsv: return .tabSeparatedText
        case .json: return .json
        }
    }
}

/// fileExporter 用。中身は作ったバイト列をそのまま書くだけ
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .tabSeparatedText, .json, .plainText] }
    var data: Data
    var type: UTType
    init(data: Data, type: UTType) { self.data = data; self.type = type }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data(); type = .plainText }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
