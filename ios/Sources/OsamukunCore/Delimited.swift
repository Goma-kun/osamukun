import Foundation

/// CSV / TSV の読み書き。拡張機能 `sidepanel.js` の「CSV / TSV パーサー（ここから）〜（ここまで）」を
/// 1 対 1 で移したもの。**こちらだけ直すと、拡張とアプリで読める行が食い違う。**
/// 直したら `../test/parity_test.mjs` で両方に同じ入力を食わせて答えを比べること。
///
/// JS は UTF-16 のコード単位を 1 文字ずつ見ている。Swift の `Character` は "\r\n" を 1 文字に
/// まとめてしまうので、ここでは `unicodeScalars` で歩く（区切り・改行・引用符はすべて 1 スカラー）
public enum Delimited {
    public static let tab: Character = "\t"
    public static let comma: Character = ","

    /// Excel 由来の CSV は先頭に BOM が付くことがあるので取り除く
    public static func stripBOM(_ text: String) -> String {
        if let first = text.unicodeScalars.first, first.value == 0xFEFF {
            return String(text.unicodeScalars.dropFirst())
        }
        return text
    }

    /// ダブルクォート囲み（改行・区切り文字入りセル、"" エスケープ）に対応した分割
    public static func parse(_ text: String, delimiter: Character) -> [[String]] {
        let delim = delimiter.unicodeScalars.first!
        let quote: Unicode.Scalar = "\""
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"
        let scalars = Array(text.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < scalars.count, scalars[i + 1] == quote {
                        field.append(quote)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else if c == cr {
                    // セル内の改行も CRLF／CR を LF に揃える（\r が本文に残るとコピー時に混ざるため）
                    if i + 1 < scalars.count, scalars[i + 1] == lf { i += 1 }
                    field.append(lf)
                } else {
                    field.append(c)
                }
            } else if c == quote, field.isEmpty {
                inQuotes = true
            } else if c == delim {
                row.append(String(field))
                field = String.UnicodeScalarView()
            } else if c == lf || c == cr {
                if c == cr, i + 1 < scalars.count, scalars[i + 1] == lf { i += 1 }   // CRLF は 1 つの改行
                row.append(String(field))
                field = String.UnicodeScalarView()
                rows.append(row)
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(String(field))
            rows.append(row)
        }
        return rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    public enum Reason: String, Sendable { case ext, firstLine }

    /// 区切り文字の判定。拡張子で分かるならそれを使い、分からなければ先頭行のタブとカンマを数える。
    /// 同数（どちらも 0 を含む）ならタブ区切り扱い（スプレッドシート由来の TSV が既定のため）
    public static func detectDelimiter(_ text: String, filename: String = "") -> (delimiter: Character, reason: Reason) {
        let lower = filename.lowercased()
        if let dot = lower.lastIndex(of: ".") {
            let ext = String(lower[lower.index(after: dot)...])
            if ext == "csv" { return (comma, .ext) }
            if ext == "tsv" { return (tab, .ext) }
        }
        var tabs = 0, commas = 0, inQuotes = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { i += 1 } else { inQuotes = false }
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "\t" {
                tabs += 1
            } else if c == "," {
                commas += 1
            } else if c == "\n" || c == "\r" {
                break   // 先頭行だけを見る
            }
            i += 1
        }
        return (tabs >= commas ? tab : comma, .firstLine)
    }

    public static func field(_ s: String, delimiter: Character) -> String {
        let needs = s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r")
        return needs ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// 書き出し。ヘッダーは画面の言語に合わせて呼び出し側から渡す（既定は英語）。
    /// どちらの言語で書き出しても `templates(fromRows:)` がヘッダー行として読み飛ばせる
    public static func serialize(_ items: [Template], delimiter: Character,
                                 headers: [String] = ["Category", "Title", "Body"]) -> String {
        var lines = [headers.map { field($0, delimiter: delimiter) }.joined(separator: String(delimiter))]
        for t in items {
            lines.append([t.category, t.title, t.body].map { field($0, delimiter: delimiter) }.joined(separator: String(delimiter)))
        }
        return lines.joined(separator: "\n")
    }

    /// 解析済みの行を定型文に変換する。カテゴリ／概要／本文の 3 列に合わない行はスキップして数える
    public static func templates(fromRows rowsIn: [[String]], now: Double = Template.nowMs(),
                                 makeID: () -> String = Template.newID) -> (imported: [Template], skipped: Int) {
        var rows = rowsIn
        if let h = rows.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
           let first = h.first, first == "カテゴリ" || first == "category" {
            rows.removeFirst()
        }
        var imported: [Template] = []
        var skipped = 0
        for r in rows {
            var cells = r
            // Excel 由来の CSV は 4 列目以降に空セルが付くことがあるので、末尾の空セルだけ落とす
            while cells.count > 3, cells.last!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cells.removeLast() }
            guard cells.count == 3 else { skipped += 1; continue }
            let t = Template(id: makeID(),
                             category: cells[0].trimmingCharacters(in: .whitespacesAndNewlines),
                             title: cells[1].trimmingCharacters(in: .whitespacesAndNewlines),
                             body: cells[2], createdAt: now, updatedAt: now)
            if t.isBlank { skipped += 1; continue }
            imported.append(t)
        }
        return (imported, skipped)
    }

    /// 拡張の JSON エクスポート（定型文の配列）を読む。アプリ同士のやり取りにも使う
    public static func templates(fromJSON data: Data, now: Double = Template.nowMs()) throws -> [Template] {
        let decoded = try JSONDecoder().decode([Template].self, from: data)
        // 同じ id が既にあるときに上書きしてしまわないよう、取り込みは必ず新しい id にする
        return decoded.filter { !$0.isBlank }.map { t in
            Template(id: Template.newID(), category: t.category, title: t.title, body: t.body, createdAt: now, updatedAt: now)
        }
    }

    public static func json(_ items: [Template]) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(items)) ?? Data("[]".utf8)
    }
}
