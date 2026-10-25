import SwiftUI

/// 管理ウィンドウ。左に一覧（検索・カテゴリ絞り込み）、右に開いた定型文。
/// 拡張のサイドパネル（一覧→全文）を横に並べた形。Mac と iPhone で同じ
struct ManageView: View {
    @EnvironmentObject var model: AppModel
    @State private var showIO = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            detail
        }
        .navigationTitle(String(localized: "おさむくん"))
        .compactNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.selectedID = "new"
                } label: {
                    Label(String(localized: "新規"), systemImage: "plus")
                }
                .help(String(localized: "新しい定型文を追加"))
                Button {
                    showIO = true
                } label: {
                    Label(String(localized: "入出力"), systemImage: "square.and.arrow.down.on.square")
                }
                .help(String(localized: "インポート／エクスポート／元に戻す"))
            }
        }
        .sheet(isPresented: $showIO) { IOView().environmentObject(model) }
        .overlay(alignment: .bottom) { ToastView(toast: model.toast) }
        .background(Theme.bg)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField(String(localized: "検索（概要・本文・カテゴリ）"), text: $model.query)
                    .textFieldStyle(.roundedBorder)
                CategoryPicker(selection: $model.category, categories: model.categories)
            }
            .padding(10)
            meta
            list
        }
        .background(Theme.bg)
    }

    @ViewBuilder
    private var meta: some View {
        if !model.templates.isEmpty {
            HStack {
                let total = model.templates.count
                let n = model.filtered.count
                Text(n == total ? String(localized: "\(total)件") : String(localized: "\(n)件 / 全\(total)件"))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                VersionBadge()
            }
            .padding(.horizontal, 12).padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.templates.isEmpty {
            EmptyState()
        } else if model.filtered.isEmpty {
            VStack(spacing: 6) {
                Text("見つかりませんでした").font(.system(size: 14, weight: .semibold))
                Text("検索語やカテゴリを変えてみてください。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedID) {
                ForEach(model.filtered) { t in
                    TemplateRow(template: t) {
                        Platform.copyToPasteboard(t.body)
                        model.showToast(String(localized: "「\(AppModel.shownTitle(t))」をコピーしました"))
                    }
                    .tag(t.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedID, id == "new" || model.template(id) != nil {
            EditView(id: id == "new" ? nil : id)
                .id(id)   // 別の定型文を開いたら、編集中の内容を引きずらない
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 36)).foregroundStyle(Theme.muted)
                Text("左の一覧から定型文を選ぶと、ここに全文が出ます").foregroundStyle(Theme.muted)
                Text("一覧の「コピー」で本文がクリップボードに入ります").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
    }
}

/// カテゴリの絞り込み。拡張の select と同じ「すべてのカテゴリ」＋登録内容からの一覧
struct CategoryPicker: View {
    @Binding var selection: String
    let categories: [String]
    var body: some View {
        Picker("", selection: $selection) {
            Text("すべてのカテゴリ").tag("")
            ForEach(categories, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(maxWidth: 170)
        .help(String(localized: "カテゴリで絞り込み"))
        .onChange(of: categories) { _, new in
            // 絞り込み中のカテゴリが消えたら「すべて」に戻す
            if !selection.isEmpty, !new.contains(selection) { selection = "" }
        }
    }
}

/// 一覧の 1 行。カテゴリのチップ＋概要＋本文の 1 行プレビュー＋コピー
struct TemplateRow: View {
    let template: Template
    var copy: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !template.category.isEmpty { CategoryChip(text: template.category) }
                    Text(AppModel.shownTitle(template)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Text(Search.preview(template.body))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(String(localized: "コピー"), action: copy)
                .buttonStyle(.bordered).controlSize(.small)
                .help(String(localized: "本文をクリップボードへ"))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// 定型文が 1 件も無いときの案内（拡張の emptyState と同じ文言）
struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("定型文がまだありません").font(.system(size: 15, weight: .bold))
            Text("「新規」から1件ずつ追加できます。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text("スプレッドシートでカテゴリ／概要／本文の3列を選択してコピーし、入出力画面に貼り付けると、そのまま取り込めます。CSV・TSV ファイルや、Chrome 拡張版おさむくんの書き出しも読み込めます。")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Button(String(localized: "サンプル定型文を読み込む")) { model.loadSamples() }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 画面下の一言。拡張の toast と同じ役目
struct ToastView: View {
    let toast: AppModel.Toast?
    var body: some View {
        if let toast {
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(toast.isError ? Theme.danger : Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 14)
                .transition(.opacity)
                .id(toast.id)
                .allowsHitTesting(false)
        }
    }
}
