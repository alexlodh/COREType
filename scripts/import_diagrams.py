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
from html import escape
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
REFERENCE = re.compile(r'\b(?P<namespace>[Ff]igures?|[Tt]ables?)\s+(?P<number>' + NUMBER + r'|\d+)\b')
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

# Source-proven pairs where a caption belongs to a before/after exercise rather
# than every animation frame. Identifiers and all table contents are retained;
# this pairs the original balance-sheet/exercise frames, never creates a table.
TABLE_FRAME_GROUPS = {
    ('macroeconomics', '6.3a'): ('figure-6-3a', 'figure-6-3b'),
    ('macroeconomics', '6.3c'): ('figure-6-3c', 'figure-6-3d'),
    ('macroeconomics', '6.3e'): ('figure-6-3e', 'figure-6-3f'),
    ('macroeconomics', '6.8a'): ('figure-6-8a', 'figure-6-8b'),
    ('macroeconomics', '6.8c'): ('figure-6-8c', 'figure-6-8d'),
    ('macroeconomics', '6.20b'): ('figure-6-20a', 'figure-6-20b'),
    ('macroeconomics', '6.20d'): ('figure-6-20c', 'figure-6-20d'),
    ('macroeconomics', '6.20f'): ('figure-6-20e', 'figure-6-20f'),
}

SAFE_TABLE_TAGS = {
    'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption', 'colgroup', 'col',
    'p', 'span', 'div', 'section', 'strong', 'b', 'em', 'i', 'sup', 'sub', 'small',
    'code', 'kbd', 'samp', 'var', 'br', 'ul', 'ol', 'li', 'dl', 'dt', 'dd',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'math', 'mrow', 'mi', 'mn', 'mo', 'ms', 'mtext', 'mfrac', 'msqrt', 'mroot',
    'msub', 'msup', 'msubsup', 'munderover', 'munder', 'mover', 'mtable', 'mtr',
    'mtd', 'semantics', 'annotation', 'mspace', 'menclose', 'mfenced', 'mpadded',
    'mstyle', 'mmultiscripts', 'mprescripts', 'none',
}
BLOCKED_TABLE_TAGS = {'script', 'style', 'img', 'iframe', 'object', 'embed', 'link',
                      'form', 'input', 'button', 'audio', 'video', 'source'}


def safe_table_style(value):
    """Retain source alignment and sizing; never accept URLs or CSS expressions."""
    declarations = []
    for declaration in value.split(';'):
        if ':' not in declaration:
            continue
        prop, raw = (s.strip().lower() for s in declaration.split(':', 1))
        if prop == 'text-align' and raw in ('left', 'right', 'center', 'justify'):
            declarations.append(prop + ':' + raw)
        elif prop == 'vertical-align' and raw in ('top', 'middle', 'bottom', 'baseline'):
            declarations.append(prop + ':' + raw)
        elif prop == 'width' and re.fullmatch(r'\d+(?:\.\d+)?(?:%|px|em|rem)', raw):
            declarations.append(prop + ':' + raw)
    return ';'.join(declarations)


def safe_table_html(node):
    """Serialize inert source table content without changing its cell text."""
    if isinstance(node, str):
        return escape(node, quote=False)
    if node.tag == 'script' and node.attrs.get('type', '').lower().startswith('math/tex'):
        return '<span class="source-math">' + ''.join(escape(str(part), quote=False) for part in node.children) + '</span>'
    if node.tag in BLOCKED_TABLE_TAGS:
        return ''
    inner = ''.join(safe_table_html(child) for child in node.children)
    tag = node.tag
    if tag == 'a':
        # Preserve source link metadata without a clickable/network-capable URL.
        href = node.attrs.get('href', '')
        return '<span data-source-href="' + escape(href, quote=True) + '">' + inner + '</span>'
    if tag not in SAFE_TABLE_TAGS:
        return inner
    attrs = {}
    for name in ('colspan', 'rowspan'):
        raw = node.attrs.get(name)
        if tag in ('td', 'th') and raw and re.fullmatch(r'\d+', raw):
            attrs[name] = raw
    for name in ('scope', 'abbr', 'title', 'headers'):
        if name in node.attrs:
            attrs[name] = node.attrs[name]
    if node.attrs.get('class'):
        attrs['class'] = ' '.join(t for t in node.attrs['class'].split() if re.fullmatch(r'[A-Za-z0-9_-]+', t))
    style = safe_table_style(node.attrs.get('style', ''))
    if style:
        attrs['style'] = style
    if tag == 'math':
        attrs['xmlns'] = 'http://www.w3.org/1998/Math/MathML'
    for name in ('display', 'mathvariant', 'stretchy', 'fence', 'separator', 'accent', 'notation', 'encoding'):
        if tag.startswith('m') or tag in ('annotation', 'math'):
            if name in node.attrs:
                attrs[name] = node.attrs[name]
    attr_html = ''.join(' ' + k + '="' + escape(v, quote=True) + '"' for k, v in attrs.items())
    return '<' + tag + attr_html + '>' + ('' if tag in ('br', 'col') else inner + '</' + tag + '>')


def table_summary(table):
    rows = [n for n in table.descendants() if n.tag == 'tr']
    return dict(rows=len(rows), cells=sum(n.tag in ('td', 'th') for n in table.descendants()),
                headers=[n.text() for n in table.descendants() if n.tag == 'th'],
                cellText=[n.text() for n in table.descendants() if n.tag in ('td', 'th')],
                spans=[dict(tag=n.tag, text=n.text(), colspan=n.attrs.get('colspan', ''),
                            rowspan=n.attrs.get('rowspan', '')) for n in table.descendants()
                       if n.tag in ('td', 'th') and (n.attrs.get('colspan') or n.attrs.get('rowspan'))],
                sourceLinks=[n.attrs['href'] for n in table.descendants() if n.tag == 'a' and n.attrs.get('href')])


def source_table_assets(figure, book, page, number, namespace='figure'):
    own_tables = ([figure] if figure.tag == 'table' else []) + [n for n in figure.descendants() if n.tag == 'table']
    if not own_tables:
        return []
    frames = [figure]
    parent = figure.parent
    if parent and parent.has_class('slides'):
        siblings = [n for n in parent.children if isinstance(n, Node) and n.has_class('figure')]
        grouped = TABLE_FRAME_GROUPS.get((book, number))
        if grouped:
            by_id = {n.attrs.get('id'): n for n in siblings}
            assert all(id_ in by_id for id_ in grouped), (book, number, grouped)
            frames = [by_id[id_] for id_ in grouped]
        elif sum(bool(n.find_class('caption')) for n in siblings) == 1:
            # A single numbered figure with a source slideshow table sequence.
            frames = [n for n in siblings if any(t.tag == 'table' for t in n.descendants())]
    assets = []
    for frame in frames:
        tables = ([frame] if frame.tag == 'table' else []) + [n for n in frame.descendants() if n.tag == 'table']
        id_ = frame.attrs.get('id') or (namespace + '-' + number.replace('.', '-'))
        for i, table in enumerate(tables):
            assert any(n.tag in ('td', 'th') and n.text() for n in table.descendants()), (book, id_)
            fragment = safe_table_html(table)
            # Preserve original explanatory step text after the table, including
            # emphasis/math markup. Main figure caption/credits remain metadata.
            explanation_nodes = [n for n in frame.descendants() if n.has_class('slide-caption')]
            fragment += ''.join(safe_table_html(n) for n in explanation_nodes)
            sanitized = DOM()
            sanitized.feed(fragment)
            rendered_table = next(n for n in sanitized.root.descendants() if n.tag == 'table')
            before, after = table_summary(table), table_summary(rendered_table)
            assert before['cellText'] == after['cellText'], (book, id_, 'cell text changed')
            assert before['spans'] == after['spans'], (book, id_, 'spans changed')
            filename = id_ + (('-' + str(i + 1)) if len(tables) > 1 else '') + '.html'
            assets.append(dict(path='Tables/' + book + '/' + filename, kind='table',
                               source=PAGE_ORIGIN + book + '/' + page + '#' + id_,
                               alt=table.text(), html=fragment + '\n', sourceIdentifier=id_,
                               sourceTableSemanticSHA256=hashlib.sha256(safe_table_html(table).encode()).hexdigest(),
                               summary=before,
                               explanatoryText=[n.text() for n in explanation_nodes]))
    return assets


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
                    row['namespace'] = 'figure'
                    row['tableAssets'] = source_table_assets(figure, book, page.name, row['number'])
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
                        row['namespace'] = 'figure'
                        row['tableAssets'] = source_table_assets(figure, book, page.name, row['number'])
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


def inspect_numbered_tables(source_work):
    """Look for actual Table captions separately from Figure-numbered tables."""
    candidates = {}
    for book in BOOKS:
        for page in sorted((source_work / 'source' / book).glob('*.html')):
            if not re.match(r'(?:0[1-9]|10)-', page.name):
                continue
            dom = DOM()
            dom.feed(page.read_text())
            for caption in dom.root.descendants():
                if caption.tag != 'caption' and not caption.has_class('caption'):
                    continue
                match = re.match(r'^Table\s+(' + NUMBER + r'|\d+)\b', caption.text(), re.I)
                if not match:
                    continue
                container = caption.parent
                while container and container.tag != 'table' and not container.has_class('figure'):
                    container = container.parent
                if not container:
                    continue
                number = match[1]
                id_ = container.attrs.get('id') or ('table-' + number.replace('.', '-'))
                key = (book, number)
                assert key not in candidates, ('Conflicting Table captions', key)
                candidates[key] = dict(book=book, unit=int(page.name[:2]), number=number, namespace='table',
                                       caption=caption.text(), source=PAGE_ORIGIN + book + '/' + page.name + '#' + id_,
                                       page=page.name, sourceIdentifier=id_, images=[], alternativeText=[],
                                       attribution='\n'.join(n.text() for n in container.descendants() if n.has_class('source')),
                                       tableAssets=source_table_assets(container, book, page.name, number, 'table'))
    return candidates


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
                             namespace='table' if match['namespace'].lower().startswith('table') else 'figure',
                             explicitBook=named_book.group(0).strip() if named_book else ''))
    return refs


def classify(row):
    key = (row['book'], row['number'])
    if key in EXCLUDED_FIGURES:
        return None, EXCLUDED_FIGURES[key]
    if not row['images'] and row.get('tableAssets'):
        return ([], 'Original source HTML table; exact cell text, headings and row/column spans retained'), None
    if not row['images']:
        return None, 'No original image or usable source HTML table'
    images = [i for i in row['images'] if i['filename'] not in EXCLUDED_ASSETS]
    if not images and not row.get('tableAssets'):
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


def verify_tables(project, source_work):
    """Read-only source fidelity and sanitizer checks, without rebuilding assets."""
    resources = project / 'Sources/COREType/Resources'
    audit = json.loads((project / 'verification/diagram-audit.json').read_text())
    catalogue = json.loads((resources / 'Diagram-Catalog.json').read_text())
    checks = {}
    source_pages = {}
    for row in audit['tableSources']:
        source_url = row['source'].split('#', 1)[0]
        relative = source_url[len(PAGE_ORIGIN):]
        if relative not in source_pages:
            dom = DOM()
            dom.feed((source_work / 'source' / relative).read_text())
            source_pages[relative] = dom
        source_frame = next(n for n in source_pages[relative].root.descendants()
                            if n.attrs.get('id') == row['sourceIdentifier'])
        source_tables = [n for n in source_frame.descendants() if n.tag == 'table']
        rendered = DOM()
        rendered.feed((resources / row['path']).read_text())
        actual_tables = [n for n in rendered.root.descendants() if n.tag == 'table']
        actual_summary = table_summary(actual_tables[0]) if actual_tables else {}
        actual_links = [n.attrs['data-source-href'] for n in actual_tables[0].descendants()
                        if n.attrs.get('data-source-href')] if actual_tables else []
        actual_summary['sourceLinks'] = actual_links
        assert actual_tables and any(table_summary(t) == actual_summary for t in source_tables), row['path']
        assert sha(resources / row['path']) == row['sha256'], row['path']
        for node in rendered.root.descendants():
            assert node.tag not in BLOCKED_TABLE_TAGS and node.tag != 'a', (row['path'], node.tag)
            assert not any(k.lower().startswith('on') or k in ('src', 'href') for k in node.attrs), row['path']
    checks['allTableCellsHeadersSpansAndSourceLinksMatchActualHTML'] = True
    checks['allTableFilesMatchAuditHashes'] = True
    checks['allTableFragmentsInert'] = True
    by_id = {d['id']: d for d in catalogue['diagrams']}
    def fragment(id_, index=0):
        a = [a for a in by_id[id_]['assets'] if a['kind'] == 'table'][index]
        return (resources / a['path']).read_text()
    expected = ['Labour input (number of farmers)', 'Grain output (kg)', 'Average product of labour (kg/farmer)', '200', '171,000', '855']
    first = DOM()
    first.feed(fragment('microeconomics-1.8a'))
    cells = [n.text() for n in first.root.descendants() if n.tag in ('th', 'td')]
    checks['KnownFarmersAndGrainSourceValuesRetained'] = cells[:6] == expected
    checks['KnownTradeColumnSpanRetained'] = 'colspan="3"' in fragment('microeconomics-2.2c') and 'Complete specialization and trade' in fragment('microeconomics-2.2c')
    after = fragment('macroeconomics-6.3a', 1)
    checks['OriginalAfterLoanFrameRetained'] = 'After the loan' in after and 'Loan to Julia' in after
    checks['OriginalLiteralLaTeXRetained'] = r'\(X-M\)' in fragment('macroeconomics-7.6') and r'\frac' in fragment('microeconomics-7.11')
    synthetic = DOM()
    synthetic.feed('<table class="data-align-right"><tr><th colspan="3" rowspan="2">Heading</th>'
                   '<td class="align-center" style="text-align:center; width:33%; background:url(https://bad.invalid/x)">'
                   '<strong>A</strong><sub>1</sub><sup>2</sup><br> &amp; '
                   '<a href="https://source.invalid/credit">Credit</a>'
                   '<script type="math/tex">\\frac{1}{x}</script>'
                   '<math><msup><mi>x</mi><mn>2</mn></msup></math>'
                   '<script>alert(1)</script><img src="https://bad.invalid/x" onerror="alert(1)">'
                   '</td></tr></table>')
    safe = safe_table_html(next(n for n in synthetic.root.descendants() if n.tag == 'table'))
    checks['SyntheticSpansAndSemanticAlignmentPreserved'] = all(x in safe for x in ['colspan="3"', 'rowspan="2"', 'data-align-right', 'align-center', 'text-align:center;width:33%'])
    checks['SyntheticEmphasisSubscriptSuperscriptAndBreakPreserved'] = '<strong>A</strong><sub>1</sub><sup>2</sup><br>' in safe
    checks['SyntheticSourceLinkIsInertMetadata'] = '<span data-source-href="https://source.invalid/credit">Credit</span>' in safe
    checks['SyntheticTeXScriptConvertedToLiteralText'] = '<span class="source-math">\\frac{1}{x}</span>' in safe
    checks['SyntheticNativeMathMLRetained'] = '<math xmlns="http://www.w3.org/1998/Math/MathML"><msup><mi>x</mi><mn>2</mn></msup></math>' in safe
    checks['SyntheticExecutableAndExternalResourceMarkupRemoved'] = all(x not in safe for x in ['<script', '<img', 'onerror', 'alert(', 'url(', 'bad.invalid'])
    refs = passage_references(dict(book='microeconomics', text='Compare Figure 2.1 with Table 2.1 and Table 2.2.'))
    checks['FigureAndTableNumberNamespacesRemainDistinct'] = [(r['namespace'], r['number']) for r in refs] == [('figure', '2.1'), ('table', '2.1'), ('table', '2.2')]
    assert all(checks.values()), checks
    return dict(checkCount=len(checks), failures=0, actualSourceTablePanelsChecked=len(audit['tableSources']), checks=checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_work', type=Path)
    parser.add_argument('--offline', action='store_true', help='Require cached originals; never fetch')
    parser.add_argument('--verify-tables', action='store_true', help='Run read-only table source/sanitizer checks, without writing assets')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    if args.verify_tables:
        print(json.dumps(verify_tables(project, args.source_work), indent=2))
        return
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
    numbered_tables = inspect_numbered_tables(args.source_work)
    selected = {}
    mappings = {}
    explicit_crossbook = {}
    matches = []
    unresolved = []
    skipped = {}
    referenced_passages = set()
    table_referenced_passages = set()
    for passage in passages:
        ids = []
        explicit_ids = []
        for ref in passage_references(passage):
            if ref['namespace'] == 'table':
                table_referenced_passages.add(passage['id'])
            else:
                referenced_passages.add(passage['id'])
            key = (ref['book'], ref['number'])
            source_candidates = numbered_tables if ref['namespace'] == 'table' else candidates
            if key in source_candidates:
                rows = [source_candidates[key]]
                method = 'Exact numbered source figure' if not rows[0].get('panelOf') else 'Exact source slide panel identifier'
            else:
                # An unsuffixed reference can name a source figure whose actual
                # captions use a/b/etc. Only real captioned subfigures qualify.
                rows = [r for k, r in sorted(source_candidates.items()) if k[0] == key[0]
                        and re.fullmatch(re.escape(key[1]) + '[a-z]', k[1]) and not r.get('panelOf')]
                method = 'Unsuffixed reference to actual captioned subfigures'
            if not rows:
                unresolved.append(dict(passage=passage['id'], **ref, reason='No corresponding saved source ' + ref['namespace']))
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
                figure_id = row['book'] + ('-table-' if row.get('namespace') == 'table' else '-') + row['number']
                selected[figure_id] = (row, images, rationale)
                if figure_id not in ids:
                    ids.append(figure_id)
                crossbook = ref['book'] != passage['book']
                if crossbook:
                    assert ref['explicitBook'], (passage['id'], ref)
                    if figure_id not in explicit_ids:
                        explicit_ids.append(figure_id)
                matches.append(dict(passage=passage['id'], passageBook=passage['book'], mention=ref['mention'],
                                    figure=figure_id, namespace=ref['namespace'], source=row['source'], method=method,
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
    table_audits = {}
    for figure_id, (row, images, rationale) in sorted(selected.items()):
        fig_assets = []
        for i, image in enumerate(images):
            label = 'Diagram' if len(images) == 1 else 'Panel ' + str(i + 1)
            fig_assets.append(dict(path='Diagrams/' + row['book'] + '/' + image['filename'],
                                   kind='image', label=label, source=image['source'], alt=image['alt']))
        table_assets = row.get('tableAssets', [])
        for i, table in enumerate(table_assets):
            path = resources / table['path']
            path.parent.mkdir(parents=True, exist_ok=True)
            if table['path'] in table_audits:
                assert path.read_text() == table['html'], ('Conflicting source tables', table['path'])
            else:
                path.write_text(table['html'])
                audit_row = {k: v for k, v in table.items() if k not in ('html', 'alt', 'kind')}
                audit_row.update(sha256=sha(path), bytes=path.stat().st_size, kind='table',
                                 selfContained=True, cellTextAndSpansExactlyMatchSource=True)
                table_audits[table['path']] = audit_row
            label = 'Table' if len(table_assets) == 1 else 'Table ' + str(i + 1)
            fig_assets.append(dict(path=table['path'], kind='table', label=label,
                                   source=table['source'], alt=table['alt']))
        unit = row.get('unit') or int(re.match(r'E?(\d+)', row['number'])[1])
        diagrams.append(dict(id=figure_id, book=row['book'], unit=unit, number=row['number'],
                             namespace=row.get('namespace', 'figure'),
                             caption=row['caption'], source=row['source'], attribution=row['attribution'],
                             assets=fig_assets))
        classifications.append(dict(id=figure_id, source=row['source'], caption=row['caption'],
                                    rationale=rationale, sourceIdentifier=row['sourceIdentifier'],
                                    assetNames=[i['filename'] for i in images],
                                    tableAssets=[t['path'] for t in table_assets]))
        for image in row['images']:
            if image['filename'] in EXCLUDED_ASSETS:
                excluded_secondary.append(dict(figure=figure_id, source=image['source'],
                                                reason=EXCLUDED_ASSETS[image['filename']]))
    assets += [dict(path=t['path'], source=t['source'], sha256=t['sha256'], bytes=t['bytes'],
                    kind='table', selfContained=True) for t in table_audits.values()]
    catalogue = dict(version=2, diagrams=diagrams, passageFigures=mappings,
                     explicitCrossBookReferences=explicit_crossbook,
                     licence='CC BY-NC-ND 4.0',
                     commonAttribution=(resources / 'Attribution.txt').read_text().strip())
    catalogue_path = resources / 'Diagram-Catalog.json'
    catalogue_path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    assert sha(library_path) == before_sha, 'Importer modified passage library'
    assert all(resources.joinpath(a['path']).exists() for d in diagrams for a in d['assets'])
    image_ids = {d['id'] for d in diagrams if any(a['kind'] == 'image' for a in d['assets'])}
    table_ids = {d['id'] for d in diagrams if any(a['kind'] == 'table' for a in d['assets'])}
    audit = dict(version=2, passageCount=len(passages), librarySHA256=before_sha,
                 textsExactlyMatchPreparedPool=True, sourceHTMLFiles=len(html_sources),
                 numberedCandidates=len(candidates), numberedTableCandidates=len(numbered_tables),
                 selectedFigures=len(diagrams), selectedDiagrams=len(image_ids), selectedTableFigures=len(table_ids),
                 bundledAssets=len(assets), assetBytes=sum(a['bytes'] for a in assets),
                 bundledImageAssets=len(assets) - len(table_audits), bundledTableAssets=len(table_audits),
                 assetsByExtension=dict(Counter(Path(a['path']).suffix for a in assets)),
                 passagesWithNumericFigureReferences=len(referenced_passages),
                 passagesWithNumericTableReferences=len(table_referenced_passages),
                 passagesWithFigures=len(mappings),
                 passagesWithDiagrams=sum(bool(image_ids.intersection(ids)) for ids in mappings.values()),
                 passagesWithTables=sum(bool(table_ids.intersection(ids)) for ids in mappings.values()),
                 passageFigureAssociations=sum(map(len, mappings.values())),
                 explicitCrossBookReferences=explicit_crossbook,
                 matchingPolicy='Explicit Figure/Table namespace and numbers; passage book unless another book is named immediately after the reference. Exact caption numbers or exact source panel identifiers; unsuffixed references expand only to actual captioned subfigures. Image animations use unchanged original summary images. Source HTML tables retain cell text, headings, row/column spans, semantic alignment and native math markup without scripts or network dependencies. Source table slideshow frames retain their original before/after or exercise/answer contents. Photographs and decorative document imagery remain excluded.',
                 licence='CC BY-NC-ND 4.0; original assets and source captions unchanged',
                 allBundledAssetsSelfContained=True, catalogueSHA256=sha(catalogue_path),
                 sourceFiles=html_sources, assets=assets, tableSources=list(table_audits.values()),
                 classifications=classifications,
                 sourceReproductions=duplicates, excludedFigures=list(skipped.values()),
                 excludedSecondaryAssets=excluded_secondary, unresolvedReferences=unresolved,
                 ignoredUnnumberedSourceFigures=non_numbered, matches=matches)
    verification.mkdir(exist_ok=True)
    (verification / 'diagram-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    overview = {key: value for key, value in audit.items() if key not in
                ('sourceFiles', 'assets', 'tableSources', 'classifications', 'sourceReproductions', 'excludedFigures',
                 'excludedSecondaryAssets', 'unresolvedReferences', 'ignoredUnnumberedSourceFigures', 'matches')}
    overview['unresolvedReferenceReasons'] = dict(Counter(r['reason'] for r in unresolved))
    print(json.dumps(overview, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
