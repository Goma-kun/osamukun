import SwiftUI

@main
struct OsamukunApp: App {
    @StateObject private var model = AppModel.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // Mac はメニューバーに常駐する。管理ウィンドウと設定は AppWindows が NSWindow で開く
        // （SwiftUI の Window だと、ホットキーやメニューから確実に同じ窓を前に出す手段が無い）
        MenuBarExtra {
            Button(String(localized: "定型文を検索して貼り付け")) { SearchPanelController.shared.show() }
            Divider()
            Button(String(localized: "定型文を管理…")) { AppWindows.openManage() }
            Button(String(localized: "設定…")) { AppWindows.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Text(String(localized: "呼び出し：") + HotKey.shared.combo.display)
            Divider()
            Button(String(localized: "おさむくんを終了")) { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        #else
        WindowGroup {
            ManageView().environmentObject(model)
        }
        #endif
    }
}

#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.shared.onPress = { SearchPanelController.shared.toggle() }
        HotKey.shared.register()
        ensureEditMenu()
        // 初回だけ管理ウィンドウを開いて、何のアプリか分かるようにする（2 回目からはメニューバーだけ）
        if !UserDefaults.standard.bool(forKey: "didOpenOnce") {
            UserDefaults.standard.set(true, forKey: "didOpenOnce")
            AppWindows.openManage()
        }
    }

    /// Dock に出ないアプリでも、文字入力欄で ⌘C／⌘V／⌘A が効くように編集メニューを用意しておく
    private func ensureEditMenu() {
        let main = NSApp.mainMenu ?? NSMenu()
        if main.items.contains(where: { $0.submenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } ?? false }) { return }
        let edit = NSMenu(title: String(localized: "編集"))
        edit.addItem(withTitle: String(localized: "取り消す"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "やり直す"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "カット"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "コピー"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "ペースト"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "すべてを選択"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: String(localized: "編集"), action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.openManage()
        return false
    }
}

/// 管理ウィンドウと設定ウィンドウ。どちらも 1 枚だけ。
/// Dock に出ないアプリなので、開くときに前面へ出し、全部閉じたら元の「メニューバーだけ」に戻す
@MainActor
enum AppWindows {
    private static var manage: NSWindow?
    private static var settings: NSWindow?

    static func openManage() { open(&manage, title: String(localized: "おさむくん"), size: NSSize(width: 860, height: 580), min: NSSize(width: 640, height: 420), frameName: "ManageWindow") {
        ManageView().environmentObject(AppModel.shared)
    } }

    static func openSettings() { open(&settings, title: String(localized: "おさむくんの設定"), size: NSSize(width: 520, height: 520), min: NSSize(width: 480, height: 420), frameName: "SettingsWindow") {
        SettingsView().environmentObject(AppModel.shared)
    } }

    private static func open<V: View>(_ slot: inout NSWindow?, title: String, size: NSSize, min: NSSize, frameName: String, @ViewBuilder _ content: () -> V) {
        NSApp.setActivationPolicy(.regular)
        if let w = slot {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.minSize = min
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content())
        w.setFrameAutosaveName(frameName)
        if !w.setFrameUsingName(frameName) { w.center() }
        w.delegate = Closer.shared
        slot = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate static func didClose(_ w: NSWindow) {
        if w === manage { manage = nil }
        if w === settings { settings = nil }
        if manage == nil && settings == nil { NSApp.setActivationPolicy(.accessory) }
    }

    private final class Closer: NSObject, NSWindowDelegate {
        static let shared = Closer()
        func windowWillClose(_ notification: Notification) {
            guard let w = notification.object as? NSWindow else { return }
            Task { @MainActor in AppWindows.didClose(w) }
        }
    }
}
#endif
