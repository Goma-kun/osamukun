import Foundation
import OsamukunCore

// JS 版（extension/sidepanel.js のパーサー）と答えを突き合わせるための入口。
// 標準入力に {"text": "...", "delimiter": "\t"|",", "filename": "..."} の配列を受け、
// 行ごとに {"rows": [[...]], "detect": "\t"|",", "imported": [[cat,title,body]], "skipped": n} を返す。
// アプリからは使わない。
struct Case: Decodable { var text: String; var delimiter: String; var filename: String? }
struct Out: Encodable { var rows: [[String]]; var detect: String; var imported: [[String]]; var skipped: Int; var roundtrip: String }

let input = FileHandle.standardInput.readDataToEndOfFile()
let cases = try JSONDecoder().decode([Case].self, from: input)
var outs: [Out] = []
for c in cases {
    let delim: Character = c.delimiter == "\t" ? Delimited.tab : Delimited.comma
    let text = Delimited.stripBOM(c.text)
    let rows = Delimited.parse(text, delimiter: delim)
    let detect = Delimited.detectDelimiter(text, filename: c.filename ?? "").delimiter
    var n = 0
    let r = Delimited.templates(fromRows: rows, now: 1, makeID: { n += 1; return "id\(n)" })
    let roundtrip = Delimited.serialize(r.imported, delimiter: delim)
    outs.append(Out(rows: rows, detect: String(detect), imported: r.imported.map { [$0.category, $0.title, $0.body] },
                    skipped: r.skipped, roundtrip: roundtrip))
}
let enc = JSONEncoder()
enc.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try enc.encode(outs))
