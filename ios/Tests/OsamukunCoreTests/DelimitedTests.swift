import XCTest
@testable import OsamukunCore

/// 拡張の `test/parser_test.mjs` と同じ場面を Swift 側で確かめる
final class DelimitedTests: XCTestCase {
    static let data: [(String, String, String)] = [
        ("挨拶", "初回の挨拶", "お世話になっております。\n株式会社〇〇の△△と申します。"),
        ("依頼", "カンマ入りの本文", "品名：A, 数量：10, 納期：3月1日"),
        ("テスト", "引用符入り", "ダブルクォート（\"カギ括弧\"）を含みます。"),
        ("テスト", "タブ入り", "タブ→\t←が入っています。"),
        ("テスト", "CRLFと空行", "1行目\n\n3行目"),
        ("", "カテゴリ空", "カテゴリが空の行"),
        ("記号", "カンマ,と改行と\"引用符\"全部", "a,b\n\"c\"\td"),
    ]
    var items: [Template] { Self.data.map { Template(category: $0.0, title: $0.1, body: $0.2) } }
    func triples(_ ts: [Template]) -> [[String]] { ts.map { [$0.category, $0.title, $0.body] } }

    func testRoundTripTSV() {
        let tsv = Delimited.serialize(items, delimiter: Delimited.tab)
        let r = Delimited.templates(fromRows: Delimited.parse(Delimited.stripBOM(tsv), delimiter: Delimited.tab))
        XCTAssertEqual(r.imported.count, Self.data.count)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertEqual(triples(r.imported), triples(items))
    }

    func testRoundTripCSV() {
        let csv = Delimited.serialize(items, delimiter: Delimited.comma)
        let r = Delimited.templates(fromRows: Delimited.parse(csv, delimiter: Delimited.comma))
        XCTAssertEqual(r.imported.count, Self.data.count)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertEqual(triples(r.imported), triples(items))
    }

    func testRoundTripCSVWithBOM() {
        let csv = "\u{FEFF}" + Delimited.serialize(items, delimiter: Delimited.comma)
        let stripped = Delimited.stripBOM(csv)
        let d = Delimited.detectDelimiter(stripped, filename: "osamukun_20260804.csv")
        XCTAssertEqual(d.delimiter, Delimited.comma)
        XCTAssertEqual(d.reason, .ext)
        let r = Delimited.templates(fromRows: Delimited.parse(stripped, delimiter: d.delimiter))
        XCTAssertEqual(r.imported.first?.category, "挨拶")
        XCTAssertEqual(triples(r.imported), triples(items))
    }

    func testRoundTripJSON() throws {
        let data = Delimited.json(items)
        let back = try Delimited.templates(fromJSON: data)
        XCTAssertEqual(triples(back), triples(items))
        // 取り込みは新しい id になる（同じ id の上書きを避ける）
        XCTAssertNotEqual(back.map(\.id), items.map(\.id))
    }

    func testCRLF() {
        let csv = Delimited.serialize(items, delimiter: Delimited.comma).replacingOccurrences(of: "\n", with: "\r\n")
        let r = Delimited.templates(fromRows: Delimited.parse(csv, delimiter: Delimited.comma))
        XCTAssertEqual(r.imported.count, Self.data.count)
        XCTAssertEqual(r.skipped, 0)
        XCTAssertEqual(r.imported[0].body, "お世話になっております。\n株式会社〇〇の△△と申します。")
    }

    func testDetectDelimiter() {
        XCTAssertEqual(Delimited.detectDelimiter("a\tb\tc\td", filename: "x.csv").delimiter, Delimited.comma)
        XCTAssertEqual(Delimited.detectDelimiter("a,b,c,d", filename: "x.tsv").delimiter, Delimited.tab)
        XCTAssertEqual(Delimited.detectDelimiter("カテゴリ,概要,本文\n", filename: "x.txt").delimiter, Delimited.comma)
        XCTAssertEqual(Delimited.detectDelimiter("カテゴリ\t概要\t本文\n", filename: "x.txt").delimiter, Delimited.tab)
        XCTAssertEqual(Delimited.detectDelimiter("a\tb,c", filename: "").delimiter, Delimited.tab)
        XCTAssertEqual(Delimited.detectDelimiter("\"a,b,c,d,e\"\tx\ty\n", filename: "x.txt").delimiter, Delimited.tab)
        XCTAssertEqual(Delimited.detectDelimiter("a\tb\tc\nx,y,z,w,v,u\n", filename: "x.txt").delimiter, Delimited.tab)
        XCTAssertEqual(Delimited.detectDelimiter("a\tb\tc\n", filename: "x.txt").reason, .firstLine)
    }

    func testSkipsMismatchedColumns() {
        let csv = "カテゴリ,概要,本文\nA,タイトル1,本文1\nB,列が2つしかない\nC,タイトル2,本文2,余計な列\nD,タイトル3,本文3,\n"
        let r = Delimited.templates(fromRows: Delimited.parse(csv, delimiter: Delimited.comma))
        XCTAssertEqual(r.imported.count, 2)
        XCTAssertEqual(r.skipped, 2)
        XCTAssertEqual(r.imported.map(\.category), ["A", "D"])
        let r2 = Delimited.templates(fromRows: Delimited.parse("カテゴリ,概要,本文\nA,t1,b1\nB,t2,b2,x\n", delimiter: Delimited.comma))
        XCTAssertEqual([r2.imported.count, r2.skipped], [1, 1])
    }

    func testHeaderRows() {
        XCTAssertEqual(Delimited.templates(fromRows: Delimited.parse("カテゴリ,概要,本文\nA,t,b\n", delimiter: Delimited.comma)).imported.count, 1)
        XCTAssertEqual(Delimited.templates(fromRows: Delimited.parse("category,title,body\nA,t,b\n", delimiter: Delimited.comma)).imported.count, 1)
        XCTAssertEqual(Delimited.templates(fromRows: Delimited.parse("A,t,b\n", delimiter: Delimited.comma)).imported.count, 1)
        for headers in [["Category", "Title", "Body"], ["カテゴリ", "概要", "本文"]] {
            let csv = Delimited.serialize(items, delimiter: Delimited.comma, headers: headers)
            let r = Delimited.templates(fromRows: Delimited.parse(csv, delimiter: Delimited.comma))
            XCTAssertEqual([r.imported.count, r.skipped], [Self.data.count, 0])
        }
    }

    func testBodyOnlyEmptyIsImported() {
        let r = Delimited.templates(fromRows: Delimited.parse("A\tタイトルのみ\t\n", delimiter: Delimited.tab))
        XCTAssertEqual([r.imported.count, r.skipped], [1, 0])
        XCTAssertEqual(r.imported[0].body, "")
    }

    func testBlankRowsAreDropped() {
        let r = Delimited.templates(fromRows: Delimited.parse("A\tt\tb\n\n \t\t\n", delimiter: Delimited.tab))
        XCTAssertEqual([r.imported.count, r.skipped], [1, 0])
    }

    func testFieldQuoting() {
        XCTAssertEqual(Delimited.field("a,b", delimiter: Delimited.comma), "\"a,b\"")
        XCTAssertEqual(Delimited.field("a,b", delimiter: Delimited.tab), "a,b")
        XCTAssertEqual(Delimited.field("a\tb", delimiter: Delimited.tab), "\"a\tb\"")
        XCTAssertEqual(Delimited.field("a\"b", delimiter: Delimited.comma), "\"a\"\"b\"")
        XCTAssertEqual(Delimited.field("a\nb", delimiter: Delimited.comma), "\"a\nb\"")
    }

    /// 配布サンプル sample_import.tsv / .csv（リポジトリ直下）が同じ 6 件として読める
    func testShippedSamples() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let tsvText = try String(contentsOf: root.appendingPathComponent("sample_import.tsv"), encoding: .utf8)
        let csvText = try String(contentsOf: root.appendingPathComponent("sample_import.csv"), encoding: .utf8)
        let tsv = Delimited.templates(fromRows: Delimited.parse(Delimited.stripBOM(tsvText), delimiter: Delimited.tab))
        let csv = Delimited.templates(fromRows: Delimited.parse(Delimited.stripBOM(csvText), delimiter: Delimited.comma))
        XCTAssertEqual(tsv.imported.count, 6)
        XCTAssertEqual(csv.imported.count, 6)
        XCTAssertEqual(tsv.skipped + csv.skipped, 0)
        XCTAssertEqual(triples(csv.imported), triples(tsv.imported))
        let kigou = tsv.imported.first { $0.title.contains("記号入り") }!
        XCTAssertFalse(kigou.body.contains("\"\""))
        XCTAssertTrue(kigou.body.contains("\"カギ括弧\""))
        XCTAssertTrue(kigou.body.contains("\t"))
    }
}
