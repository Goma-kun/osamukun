// sidepanel.js の CSV/TSV パーサー部分をそのまま切り出して検証する
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// このファイルの場所を基準にする（どこから実行しても動くように）
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(ROOT, 'extension/sidepanel.js');
const src = fs.readFileSync(SRC, 'utf8');
const start = src.indexOf('// ===== CSV / TSV パーサー（ここから）=====');
const end = src.indexOf('// ===== CSV / TSV パーサー（ここまで）=====');
if (start < 0 || end < 0) throw new Error('マーカーが見つかりません');
const block = src.slice(start, end);

let seq = 0;
const prelude = 'function uuid() { return "id" + (++__seq); }\nlet __seq = 0;\n';
const mod = new Function(
  `${prelude}${block}
   return { stripBOM, parseDelimited, detectDelimiter, delimitedField, toDelimited, rowsToTemplates, TAB, COMMA };`
)();

const { stripBOM, parseDelimited, detectDelimiter, delimitedField, toDelimited, rowsToTemplates, TAB, COMMA } = mod;

let pass = 0;
let fail = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
    console.log(`  ok   ${name}`);
  } else {
    fail++;
    console.log(`  FAIL ${name}\n       期待: ${e}\n       実際: ${a}`);
  }
}

// ===== テストデータ：日本語・改行入り本文・カンマ入り本文・引用符・タブ =====
const DATA = [
  { category: '挨拶', title: '初回の挨拶', body: 'お世話になっております。\n株式会社〇〇の△△と申します。' },
  { category: '依頼', title: 'カンマ入りの本文', body: '品名：A, 数量：10, 納期：3月1日' },
  { category: 'テスト', title: '引用符入り', body: 'ダブルクォート（"カギ括弧"）を含みます。' },
  { category: 'テスト', title: 'タブ入り', body: 'タブ→\t←が入っています。' },
  { category: 'テスト', title: 'CRLFと空行', body: '1行目\n\n3行目' },
  { category: '', title: 'カテゴリ空', body: 'カテゴリが空の行' },
  { category: '記号', title: 'カンマ,と改行と"引用符"全部', body: 'a,b\n"c"\td' },
];

console.log('== ラウンドトリップ（TSV） ==');
{
  const tsv = toDelimited(DATA, TAB);
  const { imported, skipped } = rowsToTemplates(parseDelimited(stripBOM(tsv), TAB));
  check('件数', imported.length, DATA.length);
  check('スキップ0', skipped, 0);
  check(
    '内容一致',
    imported.map((t) => [t.category, t.title, t.body]),
    DATA.map((t) => [t.category, t.title, t.body])
  );
}

console.log('== ラウンドトリップ（CSV） ==');
{
  const csv = toDelimited(DATA, COMMA);
  const { imported, skipped } = rowsToTemplates(parseDelimited(stripBOM(csv), COMMA));
  check('件数', imported.length, DATA.length);
  check('スキップ0', skipped, 0);
  check(
    '内容一致',
    imported.map((t) => [t.category, t.title, t.body]),
    DATA.map((t) => [t.category, t.title, t.body])
  );
}

console.log('== ラウンドトリップ（CSV + BOM、エクスポートと同じ形） ==');
{
  const csv = '﻿' + toDelimited(DATA, COMMA);
  const stripped = stripBOM(csv);
  const { delimiter } = detectDelimiter(stripped, 'osamukun_20260804.csv');
  check('区切り判定', delimiter, COMMA);
  const { imported } = rowsToTemplates(parseDelimited(stripped, delimiter));
  check('先頭カテゴリにBOMが残らない', imported[0].category, '挨拶');
  check(
    '内容一致',
    imported.map((t) => [t.category, t.title, t.body]),
    DATA.map((t) => [t.category, t.title, t.body])
  );
}

console.log('== ラウンドトリップ（JSON） ==');
{
  const json = JSON.stringify(DATA.map((t, i) => ({ id: 'x' + i, ...t, createdAt: 1, updatedAt: 1 })), null, 2);
  const back = JSON.parse(json);
  check(
    '内容一致',
    back.map((t) => [t.category, t.title, t.body]),
    DATA.map((t) => [t.category, t.title, t.body])
  );
}

console.log('== CRLF ==');
{
  const csv = toDelimited(DATA, COMMA).replace(/\n/g, '\r\n'); // セル内改行も含めCRLF化
  const { imported, skipped } = rowsToTemplates(parseDelimited(csv, COMMA));
  check('件数', imported.length, DATA.length);
  check('スキップ0', skipped, 0);
  check('セル内改行がLFに正規化される', imported[0].body, 'お世話になっております。\n株式会社〇〇の△△と申します。');
}

console.log('== 区切り文字の自動判定 ==');
{
  check('拡張子 .csv', detectDelimiter('a\tb\tc\td', 'x.csv'), { delimiter: COMMA, reason: 'ext' });
  check('拡張子 .tsv', detectDelimiter('a,b,c,d', 'x.tsv'), { delimiter: TAB, reason: 'ext' });
  check('.txt でカンマ多数', detectDelimiter('カテゴリ,概要,本文\n', 'x.txt').delimiter, COMMA);
  check('.txt でタブ多数', detectDelimiter('カテゴリ\t概要\t本文\n', 'x.txt').delimiter, TAB);
  check('拡張子なし・同数はタブ', detectDelimiter('a\tb,c', '').delimiter, TAB);
  check('引用符内の区切りは数えない', detectDelimiter('"a,b,c,d,e"\tx\ty\n', 'x.txt').delimiter, TAB);
  check('先頭行だけ見る', detectDelimiter('a\tb\tc\nx,y,z,w,v,u\n', 'x.txt').delimiter, TAB);
}

console.log('== 列数の不一致をスキップ ==');
{
  const csv = 'カテゴリ,概要,本文\nA,タイトル1,本文1\nB,列が2つしかない\nC,タイトル2,本文2,余計な列\nD,タイトル3,本文3,\n';
  const { imported, skipped } = rowsToTemplates(parseDelimited(csv, COMMA));
  // B は2列しかないのでスキップ、C は4列目に中身があるのでスキップ、D は末尾が空列なので3列扱い
  check('読み込み件数', imported.length, 2);
  check('スキップ件数', skipped, 2);
  check(
    '末尾の空列は無視して取り込む',
    imported.map((t) => t.category),
    ['A', 'D']
  );
}
{
  const csv = 'カテゴリ,概要,本文\nA,t1,b1\nB,t2,b2,x\n';
  const { imported, skipped } = rowsToTemplates(parseDelimited(csv, COMMA));
  check('4列目に中身があればスキップ', [imported.length, skipped], [1, 1]);
}

console.log('== ヘッダー行の扱い ==');
{
  check('日本語ヘッダーを飛ばす', rowsToTemplates(parseDelimited('カテゴリ,概要,本文\nA,t,b\n', COMMA)).imported.length, 1);
  check('英語ヘッダーを飛ばす', rowsToTemplates(parseDelimited('category,title,body\nA,t,b\n', COMMA)).imported.length, 1);
  check('ヘッダーなしでも読める', rowsToTemplates(parseDelimited('A,t,b\n', COMMA)).imported.length, 1);
}

console.log('== 書き出しヘッダーは言語ごとに変わっても読み戻せる ==');
{
  // v1.8.0 でヘッダーを画面の言語に合わせるようにした。どちらで書き出しても
  // 自分で読み戻せること（＝ヘッダー行が定型文として混ざらないこと）を確認する
  for (const [name, headers] of [
    ['既定（英語）', undefined],
    ['日本語', ['カテゴリ', '概要', '本文']],
    ['英語', ['Category', 'Title', 'Body']],
  ]) {
    const csv = toDelimited(DATA, COMMA, headers);
    const { imported, skipped } = rowsToTemplates(parseDelimited(csv, COMMA));
    check(`${name}ヘッダーの往復`, [imported.length, skipped], [DATA.length, 0]);
  }
}

console.log('== 本文だけ空の行は取り込む（v1.0.0の挙動維持） ==');
{
  const { imported, skipped } = rowsToTemplates(parseDelimited('A\tタイトルのみ\t\n', TAB));
  check('取り込まれる', [imported.length, skipped], [1, 0]);
  check('本文は空文字', imported[0].body, '');
}

console.log('== 配布サンプル sample_import.tsv / .csv ==');
{
  const read = (file, delim) =>
    rowsToTemplates(parseDelimited(stripBOM(fs.readFileSync(file, 'utf8')), delim));
  const tsv = read(path.join(ROOT, 'sample_import.tsv'), TAB);
  const csv = read(path.join(ROOT, 'sample_import.csv'), COMMA);
  const byTitle = (r, part) => r.imported.find((t) => t.title.includes(part));

  check('TSV件数', tsv.imported.length, 6);
  check('TSVスキップ0', tsv.skipped, 0);
  check('CSV件数', csv.imported.length, 6);
  check('CSVスキップ0', csv.skipped, 0);
  check(
    'TSV版とCSV版の内容が一致',
    csv.imported.map((t) => [t.category, t.title, t.body]),
    tsv.imported.map((t) => [t.category, t.title, t.body])
  );

  const kigou = byTitle(tsv, '記号入り');
  check('引用符エスケープが解ける', kigou.body.includes('""'), false);
  check('カギ括弧が復元される', kigou.body.includes('"カギ括弧"'), true);
  check('セル内タブが残る', kigou.body.includes('\t'), true);
  check('セル内改行が残る', byTitle(tsv, 'オフィス移転').body.includes('\n'), true);
  check('CSVでカンマ入り本文が1セルとして読める', byTitle(csv, 'カンマ入り').body.includes('品名：〇〇, 数量：10,'), true);
}

console.log('== 引用符のエスケープ ==');
{
  check('カンマを含むセルはCSVで囲む', delimitedField('a,b', COMMA), '"a,b"');
  check('カンマを含むセルはTSVで囲まない', delimitedField('a,b', TAB), 'a,b');
  check('タブを含むセルはTSVで囲む', delimitedField('a\tb', TAB), '"a\tb"');
  check('引用符は二重化', delimitedField('a"b', COMMA), '"a""b"');
  check('改行を含むセルは囲む', delimitedField('a\nb', COMMA), '"a\nb"');
  check('普通のセルはそのまま', delimitedField('あいう', COMMA), 'あいう');
}

console.log('== 500件の解析性能 ==');
{
  const big = [];
  for (let i = 0; i < 500; i++) {
    big.push({
      category: ['挨拶', '依頼', 'お礼', '日程調整', '社内'][i % 5],
      title: `テンプレート${i}`,
      body: `お世話になっております。\n${i}番目の本文です。カンマ, と "引用符" を含みます。\nよろしくお願いいたします。`,
    });
  }
  for (const [name, delim] of [['CSV', COMMA], ['TSV', TAB]]) {
    const text = toDelimited(big, delim);
    const t0 = performance.now();
    const { imported, skipped } = rowsToTemplates(parseDelimited(text, delim));
    const ms = performance.now() - t0;
    check(`${name} 500件の往復`, [imported.length, skipped], [500, 0]);
    console.log(`       ${name} ${(text.length / 1024).toFixed(1)}KB の解析: ${ms.toFixed(1)}ms`);
  }
}

console.log(`\n結果: ${pass} 件成功 / ${fail} 件失敗`);
process.exit(fail === 0 ? 0 : 1);
