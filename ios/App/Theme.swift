import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 拡張機能の sidepanel.css と同じ色（ライト）。**同じ製品に見えることが大事**なので、
/// ライト側を変えるときは向こうの :root も一緒に変える。ダークはアプリ版だけ（拡張はライト固定）。
/// 青い文字を黒い背景に置くと沈むので、前景の青（tint）は背景の青（primary）と分けて持つ
enum Theme {
    static let primary  = dynamic(light: 0x2563EB, dark: 0x3B82F6)
    static let tint     = dynamic(light: 0x2563EB, dark: 0x8AB4FF)
    static let bg       = dynamic(light: 0xF8FAFC, dark: 0x14181F)
    static let surface  = dynamic(light: 0xFFFFFF, dark: 0x1E242E)
    static let border   = dynamic(light: 0xE2E8F0, dark: 0x343C4A)
    static let text     = dynamic(light: 0x1E293B, dark: 0xE6EAF2)
    static let muted    = dynamic(light: 0x64748B, dark: 0x9AA4B8)
    static let danger   = dynamic(light: 0xDC2626, dark: 0xF06060)
    static let selected = dynamic(light: 0xEFF6FF, dark: 0x1F2E4A)
    /// カテゴリのチップ（拡張の .item-category と同じ、青地に青文字）
    static let chipBg   = dynamic(light: 0xEFF6FF, dark: 0x24344F)
    /// 版バッジ（拡張の .version-badge と同じ、黄）
    static let badgeBg  = dynamic(light: 0xFEF3C7, dark: 0x4A3A10)
    static let badgeFg  = dynamic(light: 0x92400E, dark: 0xF5D28A)
    /// 保存直後の緑バー／未保存の黄バー
    static let savedBg  = dynamic(light: 0xECFDF5, dark: 0x14301F)
    static let savedFg  = dynamic(light: 0x047857, dark: 0x6EE7B7)
    static let dirtyBg  = dynamic(light: 0xFFFBEB, dark: 0x3A2E0E)
    static let dirtyFg  = dynamic(light: 0x92400E, dark: 0xF5D28A)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        return Color(UIColor { tc in tc.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
        #else
        return Color(NSColor(name: nil) { app in
            let isDark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ns(isDark ? dark : light)
        })
        #endif
    }

    #if os(iOS)
    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    #else
    private static func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    #endif
}

/// カテゴリのチップ。一覧・検索パネル・編集画面で同じ見た目にする
struct CategoryChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }
}

/// 版バッジ（拡張のヘッダーと同じ）。修正したら番号を上げる
struct VersionBadge: View {
    var body: some View {
        Text("v" + AppInfo.version)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.badgeFg)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Theme.badgeBg, in: Capsule())
    }
}

enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
    /// 画面の言語が日本語か。サンプル定型文と CSV のヘッダーの出し分けに使う
    static var isJapanese: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("ja") ?? false }
}
