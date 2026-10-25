#if os(macOS)
import AppKit
import SwiftUI

/// 呼び出しパネルの状態。パネルを開くたびに検索語は空にする（毎回まっさらから探せるように）
@MainActor
final class PanelState: ObservableObject {
    @Published var query = "" { didSet { resetSelection() } }
    @Published var category = "" { didSet { resetSelection() } }
    @Published var selected = 0
    /// 貼り付けの許可があるか。パネルを開くたびに見直す
    @Published var trusted = Paster.isTrusted

    var model: AppModel { AppModel.shared }
    var filtered: [Template] { Search.filter(model.templates, query: query, category: category) }

    private func resetSelection() { selected = 0 }

    func move(_ delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selected = max(0, min(n - 1, selected + delta))
    }
}

/// Spotlight のように画面の上のほうに浮かぶ、ほかのアプリを前面にしたままのパネル。
/// `.nonactivatingPanel` なので、文字を打っていても「直前のアプリ」が前面のまま＝そこへ貼り付けられる
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchPanelController {
    static let shared = SearchPanelController()

    let state = PanelState()
    private var panel: SearchPanel?
    private var keyMonitor: Any?
    private var resignObserver: Any?
    /// パネルを開いたとき前面だったアプリ（貼り付け先）
    private var targetApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let p = panel ?? makePanel()
        targetApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0 }
        state.query = ""
        state.selected = 0
        state.trusted = Paster.isTrusted
        place(p)
        p.makeKeyAndOrderFront(nil)
        installMonitors(p)
        // SwiftUI の中の NSTextField は最初の描画のあとにできるので、今と次の周回の両方で向ける
        focusField(p)
        DispatchQueue.main.async { [weak self] in self?.focusField(p) }
    }

    /// 検索欄にキーボードを向ける。前面のアプリを変えないパネルでは SwiftUI の @FocusState が効かないので、
    /// NSTextField を探して自分でファーストレスポンダにする
    private func focusField(_ p: NSPanel) {
        func find(_ v: NSView) -> NSTextField? {
            if let f = v as? NSTextField, f.isEditable { return f }
            for c in v.subviews { if let f = find(c) { return f } }
            return nil
        }
        if let v = p.contentView, let f = find(v) {
            p.makeFirstResponder(f)
            f.currentEditor()?.selectAll(nil)
        }
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    /// 選んだ定型文を貼り付ける（許可が無いときと ⌘↩ のときはコピーまで）
    func choose(_ t: Template, copyOnly: Bool) {
        let target = targetApp
        hide()
        Task { @MainActor in
            let title = AppModel.shownTitle(t)
            if copyOnly {
                Platform.copyToPasteboard(t.body)
                HUD.show(String(localized: "「\(title)」をコピーしました"))
                return
            }
            let pasted = await Paster.paste(t.body, target: target)
            if pasted {
                HUD.show(String(localized: "「\(title)」を貼り付けました"))
            } else {
                HUD.show(String(localized: "「\(title)」をコピーしました。⌘V で貼り付けてください"))
            }
        }
    }

    private func makePanel() -> SearchPanel {
        let p = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 480, height: 300)
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.backgroundColor = .clear
        p.isOpaque = false
        let host = NSHostingView(rootView: SearchPanelView(state: state, controller: self))
        p.contentView = host
        panel = p
        return p
    }

    /// マウスのある画面の上から 1/5 の高さに、横は中央
    private func place(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let size = p.frame.size
        let x = f.midX - size.width / 2
        let y = f.maxY - f.height * 0.2 - size.height
        p.setFrameOrigin(NSPoint(x: x, y: max(f.minY, y)))
    }

    private func installMonitors(_ p: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === p else { return e }
            return self.handle(e) ? nil : e
        }
        // 外をクリックしてキーでなくなったら閉じる（Spotlight と同じ）
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// ↑↓ で選ぶ、↩ で貼り付け、⌘↩ でコピーだけ、⎋ で閉じる。
    /// 日本語入力の変換中（未確定の文字がある）の ↩ は変換の確定なので横取りしない
    private func handle(_ e: NSEvent) -> Bool {
        if let tv = panel?.firstResponder as? NSTextView, tv.hasMarkedText() { return false }
        switch Int(e.keyCode) {
        case 125: state.move(1); return true
        case 126: state.move(-1); return true
        case 36, 76:
            guard state.filtered.indices.contains(state.selected) else { return true }
            choose(state.filtered[state.selected], copyOnly: e.modifierFlags.contains(.command))
            return true
        case 53: hide(); return true
        default: return false
        }
    }
}

/// パネルの中身。検索欄・カテゴリ・一覧・下の案内
struct SearchPanelView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var model = AppModel.shared
    let controller: SearchPanelController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.muted)
                PanelSearchField(text: $state.query, placeholder: String(localized: "定型文を検索（概要・本文・カテゴリ）"))
                CategoryPicker(selection: $state.category, categories: model.categories)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            list
            Divider()
            footer
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        // タイトルバーを隠した窓なので、その分のセーフエリアまで描く（空けると上に黒い帯が出る）
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var list: some View {
        let items = state.filtered
        if model.templates.isEmpty {
            VStack(spacing: 8) {
                Text("定型文がまだありません").font(.system(size: 14, weight: .semibold))
                Text("「定型文を管理」で追加するか、サンプルを読み込んでください").font(.system(size: 12)).foregroundStyle(Theme.muted)
                HStack {
                    Button(String(localized: "サンプル定型文を読み込む")) { model.loadSamples() }
                    Button(String(localized: "定型文を管理…")) { controller.hide(); AppWindows.openManage() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            Text("見つかりませんでした").foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                            row(t, selected: i == state.selected)
                                .id(t.id)
                                .onTapGesture { controller.choose(t, copyOnly: false) }
                                .onHover { if $0 { state.selected = i } }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selected) { _, i in
                    if items.indices.contains(i) { proxy.scrollTo(items[i].id, anchor: .center) }
                }
            }
        }
    }

    private func row(_ t: Template, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !t.category.isEmpty { CategoryChip(text: t.category) }
                    Text(AppModel.shownTitle(t)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                Text(Search.preview(t.body)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if selected { Text("↩").font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.tint : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.trusted {
                Text("↩ 貼り付け").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Text("⌘↩ コピーだけ").font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else {
                Text("↩ コピー（貼り付けには許可が必要です）").font(.system(size: 11)).foregroundStyle(Theme.dirtyFg)
                Button(String(localized: "許可する…")) { controller.hide(); AppWindows.openSettings(); Paster.requestTrust() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            Text("esc 閉じる").font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Button(String(localized: "定型文を管理…")) { controller.hide(); AppWindows.openManage() }
                .buttonStyle(.link).font(.system(size: 11))
            VersionBadge()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// パネルの検索欄。AppKit の NSTextField をそのまま使う（ファーストレスポンダを外から握れるようにするため）
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 20)
        f.placeholderString = placeholder
        f.delegate = context.coordinator
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.cell?.wraps = false
        f.cell?.isScrollable = true
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 作られた直後に自分へキーボードを向ける（パネルを初めて開いたとき用）
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ v: NSTextField, context: Context) {
        if v.stringValue != text { v.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchField
        init(_ p: PanelSearchField) { parent = p }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            parent.text = f.stringValue
        }
    }
}

/// 貼り付けた・コピーしたの一言を、画面の上のほうに 1.4 秒だけ出す。前面のアプリは変えない
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var task: Task<Void, Never>?

    static func show(_ text: String) {
        let p = panel ?? make()
        let host = NSHostingView(rootView:
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 9))
        )
        host.setFrameSize(host.fittingSize)
        p.setContentSize(host.fittingSize)
        p.contentView = host
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.maxY - 60 - p.frame.height))
        p.orderFrontRegardless()
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { p.orderOut(nil) }
        }
    }

    private static func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        panel = p
        return p
    }
}
#endif
