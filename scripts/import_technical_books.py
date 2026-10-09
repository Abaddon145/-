import json
import re
import sys
from pathlib import Path
import openpyxl

root = Path(__file__).resolve().parents[1]
books, untranslated, skipped = [], [], []
for source in sorted(map(Path, sys.argv[1:])):
    normal = []
    sheet = openpyxl.load_workbook(source, data_only=True).active
    for row_number, row in enumerate(sheet.values, 1):
        if row_number == 1:
            continue
        term, meaning = (str(v).strip() if v is not None else '' for v in row[:2])
        if not term or not re.search(r'[A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]', term):
            if term or meaning:
                skipped.append((source.name, row_number, term or meaning))
            continue
        if meaning:
            normal.append(dict(korean=term, meaningZh=meaning,
                category='工业术语', note=f'{source.name} · 第 {row_number} 行'))
        else:
            ko, en = bool(re.search(r'[가-힣ㄱ-ㅎㅏ-ㅣ]', term)), bool(re.search('[A-Za-z]', term))
            kind = '英韩配对' if ko and en else '仅韩文' if ko else '仅英文'
            untranslated.append(dict(korean=term, meaningZh='原表未提供中文释义',
                category='工业术语·待补中文', tags=kind,
                note=f'{source.name} · 第 {row_number} 行 · {kind} · 原表中文栏为空'))
    books.append(dict(name=source.stem+'（有中文）', sourceFileName=source.name+'#20261009-zh', words=normal))
books.append(dict(name='英文/韩文专项（无中文）', sourceFileName='technical-untranslated#20261009', words=untranslated))
(root/'assets/data/technical_word_books.json').write_text(json.dumps(dict(books=books), ensure_ascii=False, indent=2)+'\n')
lines=['# 新词表导入核对', '', '保留原表术语与拼写，不自动补写翻译。已有相同词条复用学习记录和已有释义，不覆盖用户数据。', '',
       '| 分组 | 原表记录数 |', '|---|---:|']
lines += [f"| {b['name']} | {len(b['words'])} |" for b in books]
lines += ['', '只有中文的 3 条已跳过：'+ '、'.join(x[2] for x in skipped)+'。', '', '## 原表没有中文释义的全部条目', '', '| 原表行号 | 类型 | 英文 / 韩文（原文） |', '|---:|---|---|']
for item in untranslated:
    row = re.search(r'第 (\d+) 行', item['note']).group(1)
    lines.append(f"| {row} | {item['tags']} | {item['korean']} |")
(root/'docs/technical-vocabulary-import.md').write_text('\n'.join(lines)+'\n')
print({'books':[(b['name'],len(b['words'])) for b in books],'skipped':skipped})
