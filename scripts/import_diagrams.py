#!/usr/bin/env python3
"""Bundle unchanged source diagrams for explicit figure references in the passage pool.

Uses the saved HTML and the audited library, never edits either. curl performs
build-time downloads; no network access is needed by the installed app. Reusing
already downloaded assets permits a completely offline audit with --offline.
Only original static figure images are selected, not slideshow reconstructions.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

BOOKS = ('microeconomics', 'macroeconomics')
PAGE_ORIGIN = 'https://books.core-econ.org/the-economy/'
ASSET_ORIGIN = 'https://core-media.electricbook.works/the-economy/'
NUMBER = r'E?\d+\.\d+[a-z]?'
REFERENCE = re.compile(r'\b[Ff]igures?\s+(?P<number>' + NUMBER + r')\b')
CONTINUATION = re.compile(r'\s*(?P<join>,\s*(?:and\s+)?|and\s+|to\s+|[-–—])\s*(?P<number>' + NUMBER + r')\b')
LETTER_RANGE = re.compile(r'\s*[-–—]\s*(?P<letter>[a-z])\b')
EXPLICIT_BOOK = re.compile(
    r'^\s+(?:in\s+(?:Unit\s+\d+\s+of\s+)?|of\s+)'
    r'(?:The Economy 2\.0:\s+|the\s+)?'
    r'(?P<book>microeconomics|macroeconomics)(?:\s+volume)?', re.I)
DIAGRAM_WORDS = re.compile(
    r'\b(?:diagram|chart|graph|scatterplot|histogram|map|timeline|curve|'
    r'axis|axes|flowchart|plot|matrix|schematic|rectangle)\b', re.I)

# These are actual numbered source images, reviewed by their original caption,
# alternative text and image contents. No image is inferred from a filename.
EXCLUDED_FIGURES = {
    ('microeconomics', '5.1'): 'Illustrated historical document, not a diagram',
    ('macroeconomics', '9.1'): 'Shanghai skyline photographs, not diagrams',
}
EXCLUDED_ASSETS = {
    'figure-08-25-b.png': 'Annotated satellite imagery, excluded; retain the separate line chart',
}

# Alternative descriptions for a few original summary images are terse. The
# classification evidence here is the source caption and original SVG labels;
# descriptions in slide steps are also inspected and recorded in the audit.
REVIEWED_DIAGRAMS = {
    ('microeconomics', '1.9'): 'Cause-and-effect flowchart of Malthusian population adjustment',
    ('microeconomics', '1.21'): 'Schematic flows between biosphere, households and firms',
    ('microeconomics', '2.5'): 'Chart of workers and coal input combinations for cloth production',
    ('microeconomics', '2.16'): 'Historical technical sketch of a hydraulic economic model',
    ('microeconomics', '2.18'): 'Two-panel chart and cause-and-effect flow diagram',
    ('microeconomics', '5.2'): 'Schematic assessment of efficiency and fairness',
    ('microeconomics', '6.3'): 'Flow diagram of employed, unemployed and inactive workers',
    ('microeconomics', '6.4'): 'Flow diagram of labour-market transitions',
    ('microeconomics', '7.12'): 'Chart of demand elasticity and price',
    ('microeconomics', '8.8'): 'Two-panel chart of marginal costs and bakery profit',
    ('microeconomics', 'E8.6'): 'Chart of cake supply, market price and producer equilibrium',
    ('microeconomics', '8.25'): 'Housing market supply and demand chart',
    ('microeconomics', 'E10.1'): 'Banana production cost and output chart',
    ('macroeconomics', '1.17'): 'Schematic labour-market matching and worker flows',
    ('macroeconomics', '6.13'): 'Schematic financial flows between economic sectors',
    ('macroeconomics', 'E6.2'): 'Time-series chart of policy rate and government bond yields',
    ('macroeconomics', '7.3'): 'Time-series chart of CPI inflation',
    ('macroeconomics', '7.5'): 'Model diagrams of an aggregate demand shock',
    ('macroeconomics', '7.10'): 'Time-series chart of Spanish and German inflation',
    ('macroeconomics', '7.11'): 'Model diagrams of demand shock in a common currency area',
    ('macroeconomics', '7.12'): 'Model diagrams of eurozone membership and Spanish economy',
    ('macroeconomics', '7.16'): 'Exchange-rate depreciation and inflation charts',
    ('macroeconomics', '7.17'): 'Time-series chart of Argentinian inflation and exchange rate',
    ('macroeconomics', '7.20'): 'Time-series charts of exchange rates and interest rates',
    ('macroeconomics', '9.17a'): 'Growth dynamics model chart',
    ('macroeconomics', '9.17b'): 'Growth dynamics model chart',
    ('macroeconomics', '10.11'): 'Chart of government duration and isorent curves',
    ('macroeconomics', '10.15'): 'Chart of government duration curves and tax rises',
    ('macroeconomics', 'E10.2'): 'Chart of feasible frontiers and isorent curves',
    ('macroeconomics', 'E10.3'): 'Chart of feasible frontier, income and substitution effects',
}


class Node:
    def __init__(self, tag='', attrs=None, parent=None):
        self.tag = tag
        self.attrs = dict(attrs or [])
        self.parent = parent
        self.children = []

    def has_class(self, name):
        return name in self.attrs.get('class', '').split()

    def descendants(self):
        for child in self.children:
            if isinstance(child, Node):
                yield child
                yield from child.descendants()

    def find_class(self, name):
        return next((n for n in self.descendants() if n.has_class(name)), None)

    def text(self):
        def parts(n):
            for child in n.children:
                if isinstance(child, Node):
                    yield from parts(child)
                else:
                    yield child
        return ' '.join(' '.join(parts(self)).split())


class DOM(HTMLParser):
    VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node('root')
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(Node(tag, attrs, self.stack[-1]))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_rows(figure):
    rows = {}
    for image in figure.descendants():
        if image.tag != 'img':
            continue
        url = image.attrs.get('src') or image.attrs.get('data-src')
        if not url:
            continue
        assert url.startswith(ASSET_ORIGIN), url
        row = dict(source=url, alt=image.attrs.get('alt', ''),
                   filename=url.rsplit('/', 1)[-1])
        if url not in rows or len(row['alt']) > len(rows[url]['alt']):
            rows[url] = row
    return list(rows.values())


def inspect_sources(source_work):
    candidates = defaultdict(list)
    captionless = defaultdict(list)
    non_numbered = []
    source_files = []
    for book in BOOKS:
        for page in sorted((source_work / 'source' / book).glob('*.html')):
            if not re.match(r'(?:0[1-9]|10)-', page.name):
                continue
            dom = DOM()
            dom.feed(page.read_text())
            source_files.append(dict(path=str(page.relative_to(source_work)), sha256=sha(page)))
            for figure in dom.root.descendants():
                if not figure.has_class('figure'):
                    continue
                caption = figure.find_class('caption')
                id_ = figure.attrs.get('id', '')
                number_match = re.match(r'^Figure\s+(' + NUMBER + r')\b', caption.text()) if caption else None
                source_nodes = [n for n in figure.descendants() if n.has_class('source')]
                attribution = '\n'.join(n.text() for n in source_nodes)
                imgs = image_rows(figure)
                parent = figure.parent
                # Step descriptions are source evidence for summary diagrams,
                # while only the unchanged captioned summary asset is bundled.
                evidence_root = parent if parent and parent.has_class('slides') else figure
                alternative_text = list(dict.fromkeys(n.attrs.get('alt', '') for n in evidence_root.descendants()
                                                      if n.tag == 'img' and n.attrs.get('alt')))
                row = dict(book=book, source=PAGE_ORIGIN + book + '/' + page.name + ('#' + id_ if id_ else ''),
                           page=page.name, sourceIdentifier=id_, caption=caption.text() if caption else '',
                           attribution=attribution, images=imgs, alternativeText=alternative_text,
                           summary=figure.has_class('summary'))
                if number_match:
                    row['number'] = number_match.group(1)
                    candidates[(book, row['number'])].append(row)
                elif re.fullmatch(r'figure-(?:e)?\d+-\d+[a-z]', id_) and parent and parent.has_class('slides'):
                    # A passage occasionally names an exact animation step
                    # (e.g. Figure 4.17c). Keep that source-identifiable panel.
                    summary = next((n for n in parent.children if isinstance(n, Node) and n.has_class('summary')), None)
                    parent_caption = summary.find_class('caption') if summary else None
                    if parent_caption:
                        row['number'] = id_[7:].replace('-', '.')
                        if row['number'].startswith('e'):
                            row['number'] = 'E' + row['number'][1:]
                        heading = figure.find_class('slide-heading')
                        panel_caption = figure.find_class('slide-caption')
                        row['caption'] = '\n'.join(n.text() for n in [parent_caption, heading, panel_caption] if n)
                        if not row['attribution']:
                            row['attribution'] = '\n'.join(n.text() for n in summary.descendants() if n.has_class('source'))
                        row['panelOf'] = parent_caption.text()
                        captionless[(book, row['number'])].append(row)
                else:
                    non_numbered.append(dict(book=book, source=row['source'], caption=row['caption'],
                                             assetNames=[i['filename'] for i in imgs],
                                             reason='No numbered source caption or referenced panel identifier'))
    canonical = {}
    duplicates = []
    for key, rows in candidates.items():
        image_sets = {tuple(i['source'] for i in r['images']) for r in rows}
        if len(image_sets) > 1:
            raise ValueError('Conflicting source images for figure ' + str(key))
        # Prefer the original full caption over a source reproduction.
        row = max(rows, key=lambda r: ('reproduction' not in r['sourceIdentifier'], len(r['caption']), len(r['attribution'])))
        canonical[key] = row
        if len(rows) > 1:
            duplicates.append(dict(book=key[0], number=key[1], canonicalSource=row['source'],
                                   sources=[r['source'] for r in rows], unchangedIdenticalAssets=True))
    for key, rows in captionless.items():
        if key not in canonical:
            assert len(rows) == 1, key
            canonical[key] = rows[0]
    return canonical, duplicates, non_numbered, source_files


def range_numbers(start, end):
    a = re.fullmatch(r'(E?\d+)\.(\d+)([a-z]?)', start)
    b = re.fullmatch(r'(E?\d+)\.(\d+)([a-z]?)', end)
    if not a or not b or a[1] != b[1]:
        return None
    if a[2] == b[2] and a[3] and b[3] and a[3] <= b[3]:
        return [a[1] + '.' + a[2] + chr(i) for i in range(ord(a[3]), ord(b[3]) + 1)]
    if not a[3] and not b[3] and int(a[2]) <= int(b[2]) <= int(a[2]) + 30:
        return [a[1] + '.' + str(i) for i in range(int(a[2]), int(b[2]) + 1)]
    return None


def passage_references(passage):
    text = passage['text']
    refs = []
    for match in REFERENCE.finditer(text):
        numbers = [match['number']]
        cursor = match.end()
        while True:
            continuation = CONTINUATION.match(text, cursor)
            letter = LETTER_RANGE.match(text, cursor)
            if continuation:
                end = continuation['number']
                if continuation['join'].strip() in ('to', '-', '–', '—'):
                    expanded = range_numbers(numbers[-1], end)
                    if expanded:
                        numbers = numbers[:-1] + expanded
                    else:
                        numbers.append(end)
                else:
                    numbers.append(end)
                cursor = continuation.end()
            elif letter and numbers[-1][-1].isalpha():
                end = numbers[-1][:-1] + letter['letter']
                expanded = range_numbers(numbers[-1], end)
                if expanded:
                    numbers = numbers[:-1] + expanded
                cursor = letter.end()
            else:
                break
        book = passage['book']
        named_book = EXPLICIT_BOOK.match(text[cursor:])
        if named_book:
            book = named_book['book'].lower()
        for number in numbers:
            refs.append(dict(book=book, number=number, mention=text[match.start():cursor],
                             explicitBook=named_book.group(0).strip() if named_book else ''))
    return refs


def classify(row):
    key = (row['book'], row['number'])
    if key in EXCLUDED_FIGURES:
        return None, EXCLUDED_FIGURES[key]
    if not row['images']:
        return None, 'HTML table or figure with no original static image asset'
    images = [i for i in row['images'] if i['filename'] not in EXCLUDED_ASSETS]
    if not images:
        return None, 'No diagram image remains after source image classification'
    evidence = '\n'.join(row['alternativeText'])
    word = DIAGRAM_WORDS.search(evidence)
    if word:
        rationale = 'Source alternative text identifies ' + word.group(0).lower() + ': ' + evidence[:600]
    elif key in REVIEWED_DIAGRAMS:
        rationale = 'Reviewed source figure: ' + REVIEWED_DIAGRAMS[key]
    else:
        return None, 'Insufficient diagram classification evidence; excluded conservatively'
    return (images, rationale), None


def download_asset(resource_root, book, image, offline, expected_assets):
    relative = Path('Diagrams') / book / image['filename']
    destination = resource_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        expected = expected_assets.get(relative.as_posix())
        if expected:
            if expected['source'] != image['source']:
                raise ValueError('Cached asset source changed for ' + str(relative))
            if sha(destination) != expected['sha256']:
                raise ValueError('Cached original SHA256 mismatch for ' + str(relative))
        elif offline:
            raise ValueError('No previous original hash for offline asset ' + str(relative))
    else:
        if offline:
            raise ValueError('Missing offline asset ' + str(relative))
        temp = destination.with_suffix(destination.suffix + '.part')
        subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '2',
                        '--max-time', '90', image['source'], '--output', str(temp)], check=True)
        temp.replace(destination)
    data = destination.read_bytes()
    if destination.suffix == '.svg':
        xml = ET.fromstring(data)
        assert xml.tag.endswith('svg'), destination
        external = []
        for node in xml.iter():
            if node.tag.rsplit('}', 1)[-1] in ('script', 'foreignObject'):
                raise ValueError('Executable SVG element in ' + str(destination))
            for key, value in node.attrib.items():
                name = key.rsplit('}', 1)[-1]
                if name in ('href', 'src') and value and not value.startswith(('#', 'data:')):
                    external.append(value)
                if name.lower().startswith('on'):
                    raise ValueError('SVG event handler in ' + str(destination))
                external += [url for url in re.findall(r'url\([\s\"\']*([^\)\"\']+)', value)
                             if not url.strip().startswith(('#', 'data:'))]
            if node.tag.rsplit('}', 1)[-1] == 'style' and node.text:
                external += [url for url in re.findall(r'url\([\s\"\']*([^\)\"\']+)', node.text)
                             if not url.strip().startswith(('#', 'data:'))]
                if re.search(r'@import\b', node.text, re.I):
                    raise ValueError('SVG CSS import in ' + str(destination))
        if external:
            raise ValueError('Non-self-contained SVG ' + str(destination) + ': ' + ', '.join(external))
    elif destination.suffix == '.jpg':
        assert data.startswith(b'\xff\xd8'), destination
    elif destination.suffix == '.png':
        assert data.startswith(b'\x89PNG\r\n\x1a\n'), destination
    else:
        raise ValueError('Unsupported source image ' + str(destination))
    return dict(path=relative.as_posix(), source=image['source'], sha256=sha(destination), bytes=len(data),
                selfContained=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_work', type=Path)
    parser.add_argument('--offline', action='store_true', help='Require cached originals; never fetch')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    resources = project / 'Sources/COREType/Resources'
    verification = project / 'verification'
    previous_audit = verification / 'diagram-audit.json'
    expected_assets = ({a['path']: a for a in json.loads(previous_audit.read_text())['assets']}
                       if previous_audit.exists() else {})
    library_path = resources / 'library.json'
    before_sha = sha(library_path)
    passages = json.loads(library_path.read_text())
    assert len(passages) == 6893
    pool = (args.source_work / 'random-setup-import/CORE-Random-Paragraph-Pool.txt').read_text().strip().split('|')
    assert pool == [p['text'] for p in passages], 'Passage pool integrity failed'
    candidates, duplicates, non_numbered, html_sources = inspect_sources(args.source_work)
    selected = {}
    mappings = {}
    explicit_crossbook = {}
    matches = []
    unresolved = []
    skipped = {}
    referenced_passages = set()
    for passage in passages:
        ids = []
        explicit_ids = []
        for ref in passage_references(passage):
            referenced_passages.add(passage['id'])
            key = (ref['book'], ref['number'])
            if key in candidates:
                rows = [candidates[key]]
                method = 'Exact numbered source figure' if not rows[0].get('panelOf') else 'Exact source slide panel identifier'
            else:
                # An unsuffixed reference can name a source figure whose actual
                # captions use a/b/etc. Only real captioned subfigures qualify.
                rows = [r for k, r in sorted(candidates.items()) if k[0] == key[0]
                        and re.fullmatch(re.escape(key[1]) + '[a-z]', k[1]) and not r.get('panelOf')]
                method = 'Unsuffixed reference to actual captioned subfigures'
            if not rows:
                unresolved.append(dict(passage=passage['id'], **ref, reason='No corresponding saved source figure'))
                continue
            for row in rows:
                classification, reason = classify(row)
                if not classification:
                    unresolved.append(dict(passage=passage['id'], **ref, sourceNumber=row['number'], reason=reason))
                    skipped[row['book'], row['number']] = dict(book=row['book'], number=row['number'],
                                                               source=row['source'], caption=row['caption'], reason=reason,
                                                               assetNames=[i['filename'] for i in row['images']])
                    continue
                images, rationale = classification
                figure_id = row['book'] + '-' + row['number']
                selected[figure_id] = (row, images, rationale)
                if figure_id not in ids:
                    ids.append(figure_id)
                crossbook = ref['book'] != passage['book']
                if crossbook:
                    assert ref['explicitBook'], (passage['id'], ref)
                    if figure_id not in explicit_ids:
                        explicit_ids.append(figure_id)
                matches.append(dict(passage=passage['id'], passageBook=passage['book'], mention=ref['mention'],
                                    figure=figure_id, source=row['source'], method=method,
                                    explicitOtherBook=ref['explicitBook'] if crossbook else ''))
        if ids:
            mappings[passage['id']] = ids
        if explicit_ids:
            explicit_crossbook[passage['id']] = explicit_ids
    asset_inputs = {}
    for row, images, _ in selected.values():
        for image in images:
            asset_inputs[(row['book'], image['filename'])] = image
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(download_asset, resources, book, image, args.offline, expected_assets)
                   for (book, _), image in sorted(asset_inputs.items())]
        assets = [future.result() for future in futures]
    diagrams = []
    classifications = []
    excluded_secondary = []
    for figure_id, (row, images, rationale) in sorted(selected.items()):
        fig_assets = []
        for i, image in enumerate(images):
            label = 'Diagram' if len(images) == 1 else 'Panel ' + str(i + 1)
            fig_assets.append(dict(path='Diagrams/' + row['book'] + '/' + image['filename'],
                                   label=label, source=image['source'], alt=image['alt']))
        unit = int(re.match(r'E?(\d+)', row['number'])[1])
        diagrams.append(dict(id=figure_id, book=row['book'], unit=unit, number=row['number'],
                             caption=row['caption'], source=row['source'], attribution=row['attribution'],
                             assets=fig_assets))
        classifications.append(dict(id=figure_id, source=row['source'], caption=row['caption'],
                                    rationale=rationale, sourceIdentifier=row['sourceIdentifier'],
                                    assetNames=[i['filename'] for i in images]))
        for image in row['images']:
            if image['filename'] in EXCLUDED_ASSETS:
                excluded_secondary.append(dict(figure=figure_id, source=image['source'],
                                                reason=EXCLUDED_ASSETS[image['filename']]))
    catalogue = dict(version=1, diagrams=diagrams, passageFigures=mappings,
                     explicitCrossBookReferences=explicit_crossbook,
                     licence='CC BY-NC-ND 4.0',
                     commonAttribution=(resources / 'Attribution.txt').read_text().strip())
    catalogue_path = resources / 'Diagram-Catalog.json'
    catalogue_path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    assert sha(library_path) == before_sha, 'Importer modified passage library'
    assert all(resources.joinpath(a['path']).exists() for d in diagrams for a in d['assets'])
    audit = dict(version=1, passageCount=len(passages), librarySHA256=before_sha,
                 textsExactlyMatchPreparedPool=True, sourceHTMLFiles=len(html_sources),
                 numberedCandidates=len(candidates), selectedDiagrams=len(diagrams),
                 bundledAssets=len(assets), assetBytes=sum(a['bytes'] for a in assets),
                 assetsByExtension=dict(Counter(Path(a['path']).suffix for a in assets)),
                 passagesWithNumericFigureReferences=len(referenced_passages),
                 passagesWithDiagrams=len(mappings), passageFigureAssociations=sum(map(len, mappings.values())),
                 explicitCrossBookReferences=explicit_crossbook,
                 matchingPolicy='Explicit figure numbers; passage book unless another book is named immediately after the reference. Exact caption numbers or exact source panel identifiers; unsuffixed references expand only to actual captioned subfigures. Animation sequences use unchanged original summary images. Tables with no original static image, photographs and insufficient classification evidence are excluded.',
                 licence='CC BY-NC-ND 4.0; original assets and source captions unchanged',
                 allBundledAssetsSelfContained=True, catalogueSHA256=sha(catalogue_path),
                 sourceFiles=html_sources, assets=assets, classifications=classifications,
                 sourceReproductions=duplicates, excludedFigures=list(skipped.values()),
                 excludedSecondaryAssets=excluded_secondary, unresolvedReferences=unresolved,
                 ignoredUnnumberedSourceFigures=non_numbered, matches=matches)
    verification.mkdir(exist_ok=True)
    (verification / 'diagram-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    overview = {key: value for key, value in audit.items() if key not in
                ('sourceFiles', 'assets', 'classifications', 'sourceReproductions', 'excludedFigures',
                 'excludedSecondaryAssets', 'unresolvedReferences', 'ignoredUnnumberedSourceFigures', 'matches')}
    overview['unresolvedReferenceReasons'] = dict(Counter(r['reason'] for r in unresolved))
    print(json.dumps(overview, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
