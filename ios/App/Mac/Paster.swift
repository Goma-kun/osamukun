#if os(macOS)
import AppKit
import ApplicationServices

/// 選んだ本文を「直前に使っていたアプリ」へ貼り付ける。
/// 仕組みはクリップボードに入れてから ⌘V のキー操作を送るだけ（Maccy や Paste と同じ型）。
/// キー操作を送るにはアクセシビリティの許可が要る。許可が無ければコピーまでで止め、画面でそう言う。
/// 判定も案内も **同じ「アクセシビリティ」** を見る（「入力監視」に誘導しない・Manual 17）
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// システムの許可ダイアログを出す（設定アプリのアクセシビリティ欄が開く）
    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// クリップボードに入れて、許可があれば ⌘V を送る。戻り値は貼り付けまでできたか
    /// `target` はパネルを開いたときに前面だったアプリ。自分が前面になっていたらそちらを起こしてから送る
    static func paste(_ text: String, target: NSRunningApplication?) async -> Bool {
        Platform.copyToPasteboard(text)
        guard isTrusted else { return false }
        if let target, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate()
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            try? await Task.sleep(for: .milliseconds(60))
        }
        return sendCommandV()
    }

    private static func sendCommandV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
#endif
