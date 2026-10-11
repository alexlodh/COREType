#!/usr/bin/env python3
"""Independently compare bundled tables with their saved textbook HTML.

Run from any directory:
    python3 verification/table-source-compare.py

Requires Python 3 and BeautifulSoup 4 for this optional verification tool.
Neither dependency is required by the installed app. This script deliberately
does not import or reuse the table importer's DOM parser or sanitizer.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlparse

from bs4 import BeautifulSoup
import bs4


def normalized(text):
    return " ".join(text.split())


def cell_values(table):
    return [
        (
            cell.name,
            normalized(cell.get_text(" ", strip=True)),
            str(cell.get("rowspan", "")),
            str(cell.get("colspan", "")),
        )
        for cell in table.select("th,td")
    ]


def main():
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", type=Path, default=project / "import-source/source",
        help="Saved source HTML root containing microeconomics/ and macroeconomics/",
    )
    parser.add_argument(
        "--output", type=Path, default=project / "verification/table-source-comparison.json",
        help="JSON verification report destination",
    )
    args = parser.parse_args()
    resources = project / "Sources/COREType/Resources"
    audit = json.loads((project / "verification/diagram-audit.json").read_text())
    catalogue = json.loads((resources / "Diagram-Catalog.json").read_text())
    cache = {}
    errors = []
    totals = Counter()

    def fail(path, reason, detail=None):
        record = {"path": path, "reason": reason}
        if detail is not None:
            record["detail"] = detail
        errors.append(record)

    table_records = audit["tableSources"]
    recorded_paths = [record["path"] for record in table_records]
    catalogue_paths = {
        asset["path"] for figure in catalogue["diagrams"] for asset in figure["assets"]
        if asset.get("kind", "image") == "table"
    }
    if set(recorded_paths) != catalogue_paths:
        fail("Diagram-Catalog.json", "Table audit coverage mismatch", {
            "unrecorded": sorted(catalogue_paths - set(recorded_paths)),
            "unused": sorted(set(recorded_paths) - catalogue_paths),
        })
    if len(recorded_paths) != len(set(recorded_paths)):
        fail("diagram-audit.json", "Duplicate table asset records")

    for record in table_records:
        asset_path = record["path"]
        source_url = urlparse(record["source"])
        parts = source_url.path.split("/")
        book, page = parts[-2:]
        if book not in {"microeconomics", "macroeconomics"} or not page.endswith(".html"):
            fail(asset_path, "Invalid saved source URL", record["source"])
            continue
        source_file = args.source / book / page
        if source_file not in cache:
            cache[source_file] = BeautifulSoup(source_file.read_text(), "html.parser")
        frame = cache[source_file].find(id=record["sourceIdentifier"])
        if frame is None:
            fail(asset_path, "Source frame missing")
            continue
        tables = ([frame] if frame.name == "table" else []) + frame.find_all("table")
        index = 0
        if len(tables) > 1:
            suffix = Path(asset_path).stem[len(record["sourceIdentifier"]):]
            index = int(suffix.lstrip("-")) - 1
        if not 0 <= index < len(tables):
            fail(asset_path, "Source table index unavailable", index)
            continue
        source_table = tables[index]
        data = (resources / asset_path).read_bytes()
        rendered = BeautifulSoup(data.decode("utf-8"), "html.parser")
        rendered_table = rendered.find("table")
        if rendered_table is None:
            fail(asset_path, "Bundled table missing")
            continue
        before, after = cell_values(source_table), cell_values(rendered_table)
        if before != after:
            difference = next(
                ((old, new) for old, new in zip(before, after) if old != new),
                ("cell counts", len(before), len(after)),
            )
            fail(asset_path, "Ordered cell tag, text or span mismatch", difference)
        source_rows = len(source_table.select("tr"))
        if source_rows != len(rendered_table.select("tr")):
            fail(asset_path, "Row count mismatch")
        inline_tags = ("br", "em", "strong", "sup", "sub")
        for tag in inline_tags:
            if len(source_table.select(tag)) != len(rendered_table.select(tag)):
                fail(asset_path, "Inline formatting count mismatch", tag)
        links = [
            (normalized(link.get_text(" ", strip=True)), link.get("href", ""))
            for link in source_table.select("a")
        ]
        inert_links = [
            (normalized(link.get_text(" ", strip=True)), link.get("data-source-href", ""))
            for link in rendered_table.select("[data-source-href]")
        ]
        if links != inert_links:
            fail(asset_path, "Inert source link text or metadata mismatch")
        rendered_text = normalized(rendered.get_text(" ", strip=True))
        for explanation in frame.select(".slide-caption"):
            if normalized(explanation.get_text(" ", strip=True)) not in rendered_text:
                fail(asset_path, "Source step explanation missing")
        if rendered.find([
            "script", "style", "img", "iframe", "object", "embed", "link",
            "form", "input", "button", "audio", "video", "source",
        ]):
            fail(asset_path, "Executable or network-capable element present")
        for element in rendered.find_all():
            if any(
                key.lower().startswith("on") or key.lower() in {"href", "src"}
                for key in element.attrs
            ):
                fail(asset_path, "Active attribute present")
            if re.search(r"url\s*\(|expression\s*\(|@import", element.get("style", ""), re.I):
                fail(asset_path, "Active CSS dependency present")
        if hashlib.sha256(data).hexdigest() != record["sha256"]:
            fail(asset_path, "Bundled asset hash mismatch")
        totals["tableAssets"] += 1
        totals["rows"] += source_rows
        totals["cells"] += len(before)
        totals["spanCells"] += sum(bool(cell[2] or cell[3]) for cell in before)
        totals["inlineFormats"] += sum(len(source_table.select(tag)) for tag in inline_tags)
        totals["inertLinks"] += len(links)

    source_label = str(args.source)
    try:
        source_label = args.source.relative_to(project).as_posix()
    except ValueError:
        pass
    report = {
        "version": 1,
        "method": "Independent BeautifulSoup HTML parsing of saved source and bundled fragments",
        "parserVersion": bs4.__version__,
        "sourceRoot": source_label,
        "verified": dict(totals),
        "sourceHTMLPages": len(cache),
        "catalogueSHA256": hashlib.sha256((resources / "Diagram-Catalog.json").read_bytes()).hexdigest(),
        "errors": errors,
        "passed": not errors,
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
