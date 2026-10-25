import Foundation

/// 検索と絞り込み。拡張の `applyFilter` と同じ：カテゴリが一致し、
/// 検索語（小文字化）が概要・本文・カテゴリのどれかに含まれるもの
public enum Search {
    public static func filter(_ items: [Template], query: String, category: String) -> [Template] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { t in
            if !category.isEmpty, t.category != category { return false }
            if q.isEmpty { return true }
            return t.title.lowercased().contains(q) || t.body.lowercased().contains(q) || t.category.lowercased().contains(q)
        }
    }

    /// 一覧のプレビュー。空行で行数を消費しないよう、改行をスペースに畳む
    public static func preview(_ body: String) -> String {
        body.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
