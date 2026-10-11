#!/usr/bin/env python3
"""Reproducibly import the existing prepared excerpts; never alter source files."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
from collections import Counter

class Heading(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag == 'h1': self.active = True
    def handle_endtag(self, tag):
        if tag == 'h1': self.active = False
    def handle_data(self, data):
        if self.active: self.parts.append(data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source_work', type=Path)
    args = parser.parse_args()
    src = args.source_work
    dest = Path(__file__).resolve().parents[1] / 'Sources/COREType/Resources'
    dest.mkdir(parents=True, exist_ok=True)
    library_file = src / 'core-monkeytype-saved-text-library.json'
    library = json.loads(library_file.read_text())
    manifest = {row['name']: row for row in json.loads((src/'core-monkeytype-saved-text-library-manifest.json').read_text())}
    provenance = {row['file']: row for row in json.loads((src/'paragraph_provenance.json').read_text())}
    pages = json.loads((src/'book_manifest.json').read_text())
    titles = {(book, page['file']): page['title'] for book, items in pages.items() for page in items}
    chapters = {}
    output = []
    for name, text in library.items():
        m = re.fullmatch(r'CORE (Micro|Macro) U(\d+) S(\d+) P(\d+)', name)
        assert m, name
        short, unit, section, paragraph = m.groups()
        unit, section, paragraph = map(int, (unit, section, paragraph))
        book = 'microeconomics' if short == 'Micro' else 'macroeconomics'
        row = manifest[name]
        origin = provenance[row['paragraph_path']]
        assert origin['book'] == book
        filename = origin['source'].rsplit('/', 1)[1]
        title = titles[(book, filename)]
        title_match = re.match(r'(\d+)\.(\d+)\b', title)
        assert title_match and tuple(map(int, title_match.groups())) == (unit, section), (name, title)
        assert int(filename[:2]) == unit
        if (book, unit) not in chapters:
            h = Heading(); h.feed((src/'source'/book/filename).read_text())
            heading = ' '.join(' '.join(h.parts).split())
            assert heading.startswith(f'Unit {unit} '), heading
            chapters[(book, unit)] = heading[len(f'Unit {unit} '):]
        # Saved library and random pool already share Monkeytype typography normalization.
        # Keep those exact Unicode characters and word order, with no additional cleanup.
        assert text and not text.startswith(' ') and not text.endswith(' ')
        output.append(dict(id=name, book=book, unit=unit, chapter=chapters[(book, unit)],
                           section=section, sectionTitle=title, paragraph=paragraph,
                           text=text, source=origin['source']))
    pool = (src/'random-setup-import/CORE-Random-Paragraph-Pool.txt').read_text().strip().split('|')
    assert pool == [p['text'] for p in output], 'Prepared pool differs from the saved library'
    assert len(output) == 6893
    (dest/'library.json').write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')))
    shutil.copyfile(src/'random-setup-import/README.txt', dest/'Original-Import-README.txt')
    attribution = (src/'random-setup-import/README.txt').read_text().split('ATTRIBUTION AND LICENCE\n')[1].split('\nVERIFICATION STATUS')[0].strip()
    (dest/'Attribution.txt').write_text(attribution+'\n\nCOREType uses the prepared excerpts unchanged. This is an independent offline practice app.\n')
    audit = dict(paragraphs=len(output), bookCounts=dict(Counter(p['book'] for p in output)),
                 chapterCount=len(chapters), sectionCount=len({(p['book'],p['unit'],p['section']) for p in output}),
                 unmappedParagraphs=0, mismatchedSectionNumbers=0, textsExactlyMatchPool=True,
                 originalLibrarySHA256=hashlib.sha256(library_file.read_bytes()).hexdigest(),
                 importedLibrarySHA256=hashlib.sha256((dest/'library.json').read_bytes()).hexdigest(),
                 chapterTitles=[dict(book=b, unit=u, title=t) for (b,u),t in chapters.items()],
                 sourceWork=str(src))
    (dest/'Source-Audit.json').write_text(json.dumps(audit, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps({k:v for k,v in audit.items() if k != 'chapterTitles'}, indent=2))

if __name__ == '__main__': main()
