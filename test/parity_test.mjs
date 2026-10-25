// 拡張機能（sidepanel.js）のパーサーと、アプリ版（ios/Sources/OsamukunCore/Delimited.swift）が
// 同じ入力に同じ答えを返すことを機械的に確かめる。手で書いたテストは思いついた場面しか見られないので、
// 乱数で作った壊れ気味のテキストを両方に食わせて 1 件ずつ比べる。
//   node test/parity_test.mjs            （先に swift build --package-path ios が要る）
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = fs.readFileSync(path.join(ROOT, 'extension/sidepanel.js'), 'utf8');
const start = src.indexOf('// ===== CSV / TSV パーサー（ここから）=====');
const end = src.indexOf('// ===== CSV / TSV パーサー（ここまで）=====');
const block = src.slice(start, end);
const js = new Function(
  `let __seq = 0; function uuid() { return "id" + (++__seq); } const Date = { now: () => 1 };
   ${block}
   return { reset() { __seq = 0; }, stripBOM, parseDelimited, detectDelimiter, toDelimited, rowsToTemplates, TAB, COMMA };`
)();

// 決まった乱数（SplitMix64 の 32bit 版）。落ちたときに同じ入力で再現できるように
let seed = 0x9e3779b9;
function rnd() {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const ATOMS = ['a', 'b', 'あ', '依頼', '〇〇', '😀', ' ', ',', '\t', '"', '""', '\n', '\r\n', '\r', '"a,b"', 'category', 'カテゴリ', '', '  '];
function cell() {
  let s = '';
  const n = Math.floor(rnd() * 6);
  for (let i = 0; i < n; i++) s += pick(ATOMS);
  return s;
}
const cases = [];
for (let i = 0; i < 400; i++) {
  const delimiter = rnd() < 0.5 ? js.TAB : js.COMMA;
  const kind = rnd();
  let text;
  if (kind < 0.4) {
    // きれいに書き出したもの（ヘッダーは言語ごと・列数を 2〜4 で揺らす）
    const items = Array.from({ length: Math.floor(rnd() * 5) }, () => ({ category: cell(), title: cell(), body: cell() }));
    text = js.toDelimited(items, delimiter, pick([undefined, ['カテゴリ', '概要', '本文'], ['Category', 'Title', 'Body']]));
    if (rnd() < 0.3) text = '﻿' + text;
    if (rnd() < 0.3) text = text.replace(/\n/g, '\r\n');
  } else {
    // 手で打ったような壊れたテキスト
    text = '';
    const n = Math.floor(rnd() * 40);
    for (let j = 0; j < n; j++) text += pick(ATOMS);
  }
  cases.push({ text, delimiter, filename: pick(['', 'x.csv', 'x.tsv', 'x.txt', 'A.CSV']) });
}
// 配布サンプルも混ぜる
for (const f of ['sample_import.tsv', 'sample_import.csv']) {
  cases.push({ text: fs.readFileSync(path.join(ROOT, f), 'utf8'), delimiter: f.endsWith('.tsv') ? js.TAB : js.COMMA, filename: f });
}

const probe = path.join(ROOT, 'ios/.build/debug/ok-probe');
const swiftOut = JSON.parse(execFileSync(probe, { input: JSON.stringify(cases), maxBuffer: 64 << 20 }).toString());

let fail = 0;
cases.forEach((c, i) => {
  js.reset();
  const text = js.stripBOM(c.text);
  const rows = js.parseDelimited(text, c.delimiter);
  const detect = js.detectDelimiter(text, c.filename).delimiter;
  const { imported, skipped } = js.rowsToTemplates(rows);
  const expected = {
    rows,
    detect,
    imported: imported.map((t) => [t.category, t.title, t.body]),
    skipped,
    roundtrip: js.toDelimited(imported, c.delimiter),
  };
  const actual = swiftOut[i];
  for (const k of Object.keys(expected)) {
    if (JSON.stringify(expected[k]) !== JSON.stringify(actual[k])) {
      fail++;
      console.log(`FAIL #${i} ${k}\n  input: ${JSON.stringify(c)}\n  js:    ${JSON.stringify(expected[k])}\n  swift: ${JSON.stringify(actual[k])}`);
    }
  }
});
console.log(`${cases.length} cases, ${fail} mismatches`);
process.exit(fail ? 1 : 0);
