import SwiftUI

/// 定型文の内容（読む・直す・コピー）。拡張の「全文」画面と同じ 3 状態：
/// 触っていない（バーなし）／未保存の変更あり（黄バー＋保存＋変更を取り消す）／保存直後（緑バー＋元に戻す）。
/// **触っていなければ保存ボタンを出さない。** 保存が現れること自体が「何か変えた」という合図になる
struct EditView: View {
    @EnvironmentObject var model: AppModel
    /// nil は追加
    let id: String?

    @State private var category = ""
    @State private var title = ""
    @State private var body_ = ""
    /// 開いた（または最後に保存した）時点の内容。これと比べて「触ったか」を判定する
    @State private var baseline: (String, String, String) = ("", "", "")
    @State private var justSaved = false
    @State private var savedNotice = ""
    @State private var editingID: String?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?
    enum Field { case category, title, body }

    private var isNew: Bool { editingID == nil }
    private var dirty: Bool { (category, title, body_) != baseline }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isNew ? String(localized: "定型文を追加") : String(localized: "定型文の内容"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if !isNew {
                    Button(String(localized: "本文をコピー")) {
                        guard !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            model.showToast(String(localized: "本文が空です"), isError: true); return
                        }
                        Platform.copyToPasteboard(body_)
                        model.showToast(String(localized: "本文をコピーしました"))
                    }
                    .buttonStyle(.bordered)
                }
            }

            field(String(localized: "カテゴリ")) {
                HStack(spacing: 4) {
                    TextField(String(localized: "例：依頼"), text: $category)
                        .textFieldStyle(.roundedBorder).focused($focus, equals: .category)
                    if !model.categories.isEmpty {
                        Menu {
                            ForEach(model.categories, id: \.self) { c in Button(c) { category = c } }
                        } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help(String(localized: "登録済みのカテゴリから選ぶ"))
                    }
                }
            }
            field(String(localized: "概要（一覧に表示されるタイトル）")) {
                TextField(String(localized: "例：資料送付のお願い"), text: $title)
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .title)
            }
            field(String(localized: "本文")) {
                TextEditor(text: $body_)
                    .font(Platform.bodyFont)
                    .focused($focus, equals: .body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("コピーされる本文").foregroundStyle(Theme.muted).font(Platform.bodyFont)
                                .padding(.leading, 11).padding(.top, 7).allowsHitTesting(false)
                        }
                    }
            }

            notice

            HStack(spacing: 8) {
                if dirty {
                    Button(String(localized: "保存")) { save() }
                        .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                }
                Button(String(localized: "閉じる")) { close() }.buttonStyle(.bordered)
                Spacer()
                if !isNew && !justSaved {
                    Button(String(localized: "削除"), role: .destructive) { confirmDelete = true }
                        .buttonStyle(.bordered).foregroundStyle(Theme.danger)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .onAppear(perform: load)
        .confirmationDialog(String(localized: "「\(title.isEmpty ? AppModel.untitled : title)」を削除しますか？"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "削除"), role: .destructive) { if let editingID { model.delete(id: editingID) } }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    @ViewBuilder
    private var notice: some View {
        if justSaved {
            bar(text: savedNotice, bg: Theme.savedBg, fg: Theme.savedFg) {
                Button(String(localized: "元に戻す")) { undoFromEdit() }.buttonStyle(.bordered).controlSize(.small)
            }
        } else if dirty {
            bar(text: String(localized: "保存していない変更があります"), bg: Theme.dirtyBg, fg: Theme.dirtyFg) {
                Button(String(localized: "変更を取り消す")) {
                    (category, title, body_) = baseline
                    model.showToast(String(localized: "変更を取り消しました"))
                }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func bar<C: View>(text: String, bg: Color, fg: Color, @ViewBuilder _ button: () -> C) -> some View {
        HStack {
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(fg)
            Spacer()
            button()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(bg, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 開くたびに全項目を入れ直す（一部だけだと前に開いた定型文の状態を引きずる）
    private func load() {
        editingID = id
        if let t = model.template(id) {
            category = t.category; title = t.title; body_ = t.body
        } else {
            category = model.category; title = ""; body_ = ""
        }
        justSaved = false
        baseline = (category, title, body_)
        focus = isNew ? .title : nil
        if Shot.dirty { body_ += "\n\n（追記中の文）" }   // 撮影用。Release では常に false
    }

    private func save() {
        guard let saved = model.save(id: editingID, category: category, title: title, body: body_) else { return }
        let wasNew = isNew
        // 保存後もこの画面に留まるので、次に保存したとき二重登録にならないよう対象を切り替える
        editingID = saved.id
        if model.selectedID == "new" { model.selectedID = saved.id }
        category = saved.category; title = saved.title; body_ = saved.body
        baseline = (category, title, body_)
        let shown = AppModel.shownTitle(saved)
        savedNotice = wasNew ? String(localized: "「\(shown)」の追加を保存しました") : String(localized: "「\(shown)」の編集を保存しました")
        justSaved = true
    }

    /// 保存直後の「元に戻す」。追加そのものを取り消した場合は、この定型文がもう無いので閉じる
    private func undoFromEdit() {
        model.performUndo()
        justSaved = false
        guard let t = model.template(editingID) else { model.selectedID = nil; return }
        category = t.category; title = t.title; body_ = t.body
        baseline = (category, title, body_)
    }

    private func close() {
        model.selectedID = nil
    }
}
