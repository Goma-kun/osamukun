import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// OS ごとに違うところを、ここ 1 か所にまとめる。**画面の側に `#if` を散らさない**
enum Platform {
    /// 保存先。Mac はサンドボックスの Application Support/Osamukun、iPhone も同じ相対位置
    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Osamukun", isDirectory: true)
    }

    /// クリップボードへ本文を入れる（拡張の copyText と同じ役目）
    static func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    /// 本文の入力欄。Mac は TextEditor を枠で囲んで使う
    static var bodyFont: Font { .system(size: 14) }
}

extension View {
    /// `navigationBarTitleDisplayMode` は iOS にしか無い
    @ViewBuilder
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
