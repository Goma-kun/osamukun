import Foundation

/// 定型文 1 件。**拡張機能の `chrome.storage.local` の `templates` と同じ形のまま持つ。**
/// 拡張の JSON エクスポートをそのまま読み込めること、将来 iPhone と同期するときに
/// 変換を挟まないことが狙い。時刻は拡張と同じくミリ秒（`Date.now()`）
public struct Template: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var category: String
    public var title: String
    public var body: String
    public var createdAt: Double
    public var updatedAt: Double

    public init(id: String = Template.newID(), category: String = "", title: String = "", body: String = "",
                createdAt: Double = Template.nowMs(), updatedAt: Double? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// 拡張のエクスポートは全キーを持つが、手で直した JSON に欠けがあっても読めるようにしておく
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Template.newID()
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? Template.nowMs()
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? createdAt
    }

    public static func newID() -> String { UUID().uuidString.lowercased() }
    public static func nowMs(_ date: Date = Date()) -> Double { (date.timeIntervalSince1970 * 1000).rounded(.down) }

    /// 一覧に出す名前。概要が空なら「（無題）」に相当する文言は画面側で決める
    public var isBlank: Bool { title.isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 保存ファイルの中身。定型文の配列に、同期のための印を 2 つ足しただけ。
///
/// - `updatedAt`: この入れ物を最後に書き換えた時刻（ミリ秒）
/// - `deleted`: 消した定型文の id → 消した時刻。「足し合わせ」の同期は削除を表現できない
///   （うながすくんで学んだこと）ので、消した事実も持っておく。iPhone 版と iCloud で揃えるとき
///   `Merge.snapshots` がこれを見る。拡張機能にはこの欄は無い（読み込むときは空で埋める）
public struct Snapshot: Codable, Equatable, Sendable {
    public var templates: [Template]
    public var updatedAt: Double
    public var deleted: [String: Double]

    public init(templates: [Template] = [], updatedAt: Double = 0, deleted: [String: Double] = [:]) {
        self.templates = templates
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templates = try c.decodeIfPresent([Template].self, forKey: .templates) ?? []
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        deleted = try c.decodeIfPresent([String: Double].self, forKey: .deleted) ?? [:]
    }

    /// 中身が同じか（`updatedAt` は見ない）。同期で「上げ直す必要があるか」に使う
    public func sameContent(as other: Snapshot) -> Bool {
        templates == other.templates && deleted == other.deleted
    }

    /// カテゴリの一覧。拡張と同じく登録内容から動的に作り、空は除いて日本語順に並べる
    public var categories: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in templates {
            let c = t.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty, seen.insert(c).inserted { out.append(c) }
        }
        return out.sorted { $0.compare($1, locale: Locale(identifier: "ja")) == .orderedAscending }
    }

    // MARK: - 書き換えの入口（必ずここを通す。直接 templates を触ると deleted が残らない）

    public mutating func upsert(_ t: Template, now: Double = Template.nowMs()) {
        if let i = templates.firstIndex(where: { $0.id == t.id }) {
            templates[i] = t
        } else {
            // 拡張は新規を先頭に入れる（unshift）
            templates.insert(t, at: 0)
        }
        deleted.removeValue(forKey: t.id)
        updatedAt = now
    }

    public mutating func remove(id: String, now: Double = Template.nowMs()) {
        templates.removeAll { $0.id == id }
        deleted[id] = now
        updatedAt = now
    }

    public mutating func removeAll(now: Double = Template.nowMs()) {
        for t in templates { deleted[t.id] = now }
        templates = []
        updatedAt = now
    }

    /// インポート。拡張と同じく、追記は先頭に積む
    public mutating func importTemplates(_ items: [Template], replace: Bool, now: Double = Template.nowMs()) {
        if replace {
            for t in templates { deleted[t.id] = now }
            templates = items
        } else {
            templates = items + templates
        }
        for t in items { deleted.removeValue(forKey: t.id) }
        updatedAt = now
    }

    /// 元に戻す。配列を丸ごと差し替えるので、消えた id は deleted へ、戻った id は deleted から外す
    public mutating func restore(_ items: [Template], now: Double = Template.nowMs()) {
        let after = Set(items.map(\.id))
        for t in templates where !after.contains(t.id) { deleted[t.id] = now }
        for id in after { deleted.removeValue(forKey: id) }
        templates = items
        updatedAt = now
    }
}

/// 2 台の中身を混ぜる。iPhone 版との iCloud 同期で使う（Mac 版 1.0 ではまだ呼ばない）。
/// 定型文ごとに `updatedAt` の新しいほうを採り、削除の印が更新より新しければ消す。
/// どちらの端末で混ぜても同じ答えになる（順番は「新しい入れ物」の並びを優先）
public enum Merge {
    public static func snapshots(_ a: Snapshot, _ b: Snapshot) -> Snapshot {
        let (newer, older) = a.updatedAt >= b.updatedAt ? (a, b) : (b, a)
        var deleted = newer.deleted
        for (id, at) in older.deleted where (deleted[id] ?? 0) < at { deleted[id] = at }

        var byID: [String: Template] = [:]
        var order: [String] = []
        for t in newer.templates + older.templates {
            if let cur = byID[t.id] {
                if t.updatedAt > cur.updatedAt { byID[t.id] = t }
            } else {
                byID[t.id] = t
                order.append(t.id)
            }
        }
        var out: [Template] = []
        for id in order {
            guard let t = byID[id] else { continue }
            if let d = deleted[id], d >= t.updatedAt { continue }
            // 消した後に別の端末で書き直されていたら、書き直しが勝つ（印は外す）
            deleted.removeValue(forKey: id)
            out.append(t)
        }
        return Snapshot(templates: out, updatedAt: max(a.updatedAt, b.updatedAt), deleted: deleted)
    }
}
