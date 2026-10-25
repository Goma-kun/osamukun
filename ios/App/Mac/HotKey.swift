#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// 呼び出しのショートカット。Carbon の RegisterEventHotKey を使う。
/// サンドボックスの中でも使えて、アクセシビリティの許可も要らない（NSEvent のグローバル監視は許可が要る）。
/// 既定は ⌃⇧Space。Chrome 拡張版は「既定キーなし」にしたが、Mac はぶつかっても設定で変えられるので置く
@MainActor
final class HotKey {
    struct Combo: Equatable, Codable {
        var keyCode: UInt32
        /// Carbon の修飾キー（cmdKey / optionKey / controlKey / shiftKey）
        var modifiers: UInt32

        static let `default` = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey))

        /// 画面に出す形（⌃⇧Space のように）
        var display: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + HotKey.keyName(keyCode)
        }

        /// NSEvent から作る。修飾キーが cmd / ctrl / opt のどれも無いものは受け付けない
        /// （文字キーだけだと普通の入力を奪ってしまう）
        static func from(_ e: NSEvent) -> Combo? {
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var m: UInt32 = 0
            if f.contains(.command) { m |= UInt32(cmdKey) }
            if f.contains(.option) { m |= UInt32(optionKey) }
            if f.contains(.control) { m |= UInt32(controlKey) }
            if f.contains(.shift) { m |= UInt32(shiftKey) }
            let hasReal = m & UInt32(cmdKey | optionKey | controlKey) != 0
            let isFunction = (Int(e.keyCode) >= kVK_F1 && Int(e.keyCode) <= kVK_F12) || Int(e.keyCode) == kVK_F13
                || Int(e.keyCode) == kVK_F14 || Int(e.keyCode) == kVK_F15
            guard hasReal || isFunction else { return nil }
            return Combo(keyCode: UInt32(e.keyCode), modifiers: m)
        }
    }

    static let shared = HotKey()
    private static let defaultsKey = "hotKeyCombo"

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private(set) var combo: Combo = {
        if let data = UserDefaults.standard.data(forKey: HotKey.defaultsKey),
           let c = try? JSONDecoder().decode(Combo.self, from: data) { return c }
        return .default
    }()

    func set(_ c: Combo) {
        combo = c
        UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: Self.defaultsKey)
        register()
    }

    /// 登録。すでに登録済みなら外してから入れ直す
    @discardableResult
    func register() -> Bool {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4F534D4B) /* OSMK */, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// キーコードの名前。文字キーは現在のキーボード配列で引き、特殊キーは表から
    nonisolated static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_JIS_Eisu: "英数", kVK_JIS_Kana: "かな",
        ]
        if let s = special[Int(code)] { return s }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var dead: UInt32 = 0
        let status = data.withUnsafeBytes { buf -> OSStatus in
            UCKeyTranslate(buf.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(code), UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
#endif
