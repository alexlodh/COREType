import Foundation
import TypingCore

extension TypingCoreTests {
    private var diagramResourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/COREType/Resources", isDirectory: true)
    }

    private func diagramPassage(id: String, book: String = "microeconomics", unit: Int = 1) -> Passage {
        Passage(id: id, book: book, unit: unit, chapter: "Chapter", section: 1,
                sectionTitle: "\(unit).1 Section", paragraph: 1,
                text: "See Figure 1.1.", source: "https://books.core-econ.org/the-economy/\(book)/01-01.html")
    }

    private func diagramFixture(id: String, book: String, unit: Int = 1, number: String = "1.1") -> TextbookFigure {
        TextbookFigure(id: id, book: book, unit: unit, number: number,
                      caption: "Figure \(number): Example", source: "https://books.core-econ.org/the-economy/\(book)/01-01.html",
                      attribution: "The CORE Econ Team. CC BY-NC-ND 4.0.",
                      assets: [FigureAsset(path: "Diagrams/example.png", label: "Figure \(number)", source: "https://books.core-econ.org/example.png")])
    }

    func testDiagramMatchingUsesProvenAssociationsAndBookIsolation() throws {
        let micro = diagramFixture(id: "microeconomics-1.1", book: "microeconomics")
        let macro = diagramFixture(id: "macroeconomics-1.1", book: "macroeconomics")
        let crossChapter = diagramFixture(id: "microeconomics-2.3", book: "microeconomics", unit: 2, number: "2.3")
        let p = diagramPassage(id: "micro-passage")
        let catalogue = FigureCatalogue(diagrams: [micro, macro, crossChapter], passageFigures: [
            p.id: [micro.id, macro.id, "unknown", crossChapter.id, micro.id],
            "macro-passage": [macro.id, micro.id],
            "explicit-macro-passage": [macro.id, micro.id]
        ], explicitCrossBookReferences: ["explicit-macro-passage": [micro.id]])

        // An explicit same-book cross-chapter reference is valid. Duplicate and
        // unknown identifiers must not add panels, and another book is excluded.
        XCTAssertEqual(catalogue.figures(for: p).map(\.id), [micro.id, crossChapter.id])
        XCTAssertEqual(catalogue.figures(for: diagramPassage(id: "macro-passage", book: "macroeconomics")).map(\.id), [macro.id])
        XCTAssertEqual(catalogue.figures(for: diagramPassage(id: "explicit-macro-passage", book: "macroeconomics")).map(\.id), [macro.id, micro.id])
        // Text that happens to contain a figure number is insufficient: only
        // source-proven passage associations enable the viewer.
        XCTAssertTrue(catalogue.figures(for: diagramPassage(id: "unmapped-passage")).isEmpty)
        XCTAssertTrue(FigureCatalogue().figures(for: p).isEmpty)

        let restored = try JSONDecoder().decode(FigureCatalogue.self, from: JSONEncoder().encode(catalogue))
        XCTAssertEqual(restored.diagrams, catalogue.diagrams)
        XCTAssertEqual(restored.passageFigures, catalogue.passageFigures)
        XCTAssertEqual(restored.explicitCrossBookReferences, catalogue.explicitCrossBookReferences)
        XCTAssertEqual(restored.figures(for: p), catalogue.figures(for: p))
        let older = try JSONDecoder().decode(FigureCatalogue.self, from: Data(#"{"diagrams":[],"passageFigures":{}}"#.utf8))
        XCTAssertTrue(older.explicitCrossBookReferences.isEmpty)
    }

    func testDiagramAssetsRemainInsideLocalBundle() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("COREType-diagram-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Resources", isDirectory: true)
        let diagrams = root.appendingPathComponent("Diagrams", isDirectory: true)
        let nested = diagrams.appendingPathComponent("nested", isDirectory: true)
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        let local = nested.appendingPathComponent("figure.png")
        try Data("local diagram".utf8).write(to: local)
        let outside = directory.appendingPathComponent("outside.png")
        try Data("outside bundle".utf8).write(to: outside)
        try manager.createSymbolicLink(at: diagrams.appendingPathComponent("escape.png"), withDestinationURL: outside)
        let catalogue = FigureCatalogue()
        func asset(_ path: String) -> FigureAsset { FigureAsset(path: path, label: "Figure", source: "https://example.org/original.png") }

        let resolved = catalogue.assetURL(asset("Diagrams/nested/figure.png"), root: root)
        XCTAssertTrue(resolved?.isFileURL == true)
        if let resolved { XCTAssertEqual(try Data(contentsOf: resolved), Data("local diagram".utf8)) }
        for path in ["Diagrams/missing.png", "Diagrams/nested", "Diagrams/../outside.png",
                     "Diagrams/nested/../../outside.png", "Diagrams/escape.png", "Other/figure.png",
                     outside.path, "https://example.org/figure.png"] {
            XCTAssertNil(catalogue.assetURL(asset(path), root: root))
        }
        XCTAssertNil(catalogue.assetURL(asset("Diagrams/nested/figure.png"), root: URL(string: "https://example.org/Resources")!))

        let tables = root.appendingPathComponent("Tables", isDirectory: true)
        try manager.createDirectory(at: tables, withIntermediateDirectories: true)
        let table = tables.appendingPathComponent("figure.html")
        try Data("<table><tr><th>Output</th><td>855</td></tr></table>".utf8).write(to: table)
        let outsideHTML = directory.appendingPathComponent("outside.html")
        try Data("<html>Outside the bundled table folder</html>".utf8).write(to: outsideHTML)
        try manager.createSymbolicLink(at: tables.appendingPathComponent("escape.html"), withDestinationURL: outsideHTML)
        try Data("<html>Arbitrary HTML</html>".utf8).write(to: diagrams.appendingPathComponent("arbitrary.html"))
        try Data("unsupported".utf8).write(to: tables.appendingPathComponent("figure.png"))
        func tableAsset(_ path: String, kind: String = "table") -> FigureAsset {
            FigureAsset(path: path, label: "Table", source: "https://example.org/source.html", kind: kind)
        }
        let resolvedTable = catalogue.assetURL(tableAsset("Tables/figure.html"), root: root)
        XCTAssertTrue(resolvedTable?.isFileURL == true)
        if let resolvedTable { XCTAssertEqual(try Data(contentsOf: resolvedTable), try Data(contentsOf: table)) }
        XCTAssertNil(catalogue.assetURL(asset("Tables/figure.html"), root: root))
        XCTAssertNil(catalogue.assetURL(asset("Diagrams/arbitrary.html"), root: root))
        XCTAssertNil(catalogue.assetURL(tableAsset("Diagrams/nested/figure.png"), root: root))
        XCTAssertNil(catalogue.assetURL(tableAsset("Tables/figure.html", kind: "html"), root: root))
        for path in ["Tables/figure.png", "Tables/missing.html", "Tables", "Tables/../outside.html",
                     "Tables/nested/../../outside.html", "Tables/escape.html", "Other/figure.html",
                     outsideHTML.path, "https://example.org/figure.html"] {
            XCTAssertNil(catalogue.assetURL(tableAsset(path), root: root))
        }
        // A whole resource folder must not be allowed to redirect outside the
        // bundle, even if its child paths look valid and the files exist.
        let linkedRoot = directory.appendingPathComponent("LinkedResources", isDirectory: true)
        let externalAssets = directory.appendingPathComponent("ExternalAssets", isDirectory: true)
        try manager.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
        try manager.createDirectory(at: externalAssets, withIntermediateDirectories: true)
        try Data("external table".utf8).write(to: externalAssets.appendingPathComponent("figure.html"))
        try Data("external image".utf8).write(to: externalAssets.appendingPathComponent("figure.png"))
        try manager.createSymbolicLink(at: linkedRoot.appendingPathComponent("Tables"), withDestinationURL: externalAssets)
        try manager.createSymbolicLink(at: linkedRoot.appendingPathComponent("Diagrams"), withDestinationURL: externalAssets)
        XCTAssertNil(catalogue.assetURL(tableAsset("Tables/figure.html"), root: linkedRoot))
        XCTAssertNil(catalogue.assetURL(asset("Diagrams/figure.png"), root: linkedRoot))
    }

    func testTableMetadataAndOlderDiagramSchema() throws {
        let oldAsset = try JSONDecoder().decode(FigureAsset.self, from: Data(#"{"path":"Diagrams/old.png","label":"Diagram","source":"https://example.org/old.png","alt":"Original image"}"#.utf8))
        XCTAssertEqual(oldAsset.kind, "image")
        let oldFigure = try JSONDecoder().decode(TextbookFigure.self, from: Data(#"{"id":"microeconomics-1.1","book":"microeconomics","unit":1,"number":"1.1","caption":"Figure 1.1","source":"https://example.org/source","attribution":"","assets":[{"path":"Diagrams/old.png","label":"Diagram","source":"https://example.org/old.png","alt":""}]}"#.utf8))
        XCTAssertEqual(oldFigure.namespace, "figure")
        XCTAssertFalse(oldFigure.isTable)
        let table = TextbookFigure(id: "microeconomics-table-1.1", book: "microeconomics", unit: 1,
                                  number: "1.1", caption: "Table 1.1", source: "https://example.org/source",
                                  assets: [FigureAsset(path: "Tables/one.html", label: "Table", source: "https://example.org/source", kind: "table")],
                                  namespace: "table")
        XCTAssertTrue(table.isTable)
        XCTAssertEqual(table.namespace, "table")
        XCTAssertNotEqual(table.id, oldFigure.id)
        let catalogue = FigureCatalogue(diagrams: [oldFigure, table], passageFigures: ["figure": [oldFigure.id], "table": [table.id]])
        XCTAssertEqual(catalogue.figures(for: diagramPassage(id: "figure")).map(\.namespace), ["figure"])
        XCTAssertEqual(catalogue.figures(for: diagramPassage(id: "table")).map(\.namespace), ["table"])
        let restored = try JSONDecoder().decode(TextbookFigure.self, from: JSONEncoder().encode(table))
        XCTAssertEqual(restored, table)
        XCTAssertTrue(restored.isTable)
        let empty = TextbookFigure(id: "empty", book: "microeconomics", unit: 1, number: "1.1", caption: "Empty", source: "https://example.org/source", assets: [], namespace: "table")
        XCTAssertFalse(empty.isTable)
        let mixed = TextbookFigure(id: "mixed", book: "microeconomics", unit: 1, number: "1.1", caption: "Mixed", source: "https://example.org/source", assets: [oldAsset] + table.assets)
        XCTAssertFalse(mixed.isTable)
    }

    func testActualTablesPreserveSourceCellsHeadersAndSpans() throws {
        let root = diagramResourceRoot
        let catalogue = try JSONDecoder().decode(FigureCatalogue.self, from: Data(contentsOf: root.appendingPathComponent("Diagram-Catalog.json")))
        let lib = try loadLibrary()
        let tableFigures = catalogue.diagrams.filter { $0.assets.contains { $0.kind == "table" } }
        XCTAssertFalse(tableFigures.isEmpty)
        if let passage = lib.passages.first(where: { $0.id == "CORE Micro U01 S06 P008" }) {
            XCTAssertTrue(catalogue.figures(for: passage).contains { $0.id == "microeconomics-1.8a" && $0.isTable })
        } else { XCTAssertTrue(false, "Missing known table-reference passage") }
        if let externalTable = lib.passages.first(where: { $0.id == "CORE Macro U06 S11 P029" }) {
            // "Table 2" here names an external ONS webpage. It must not be
            // mapped to an unrelated numbered table in the textbook.
            XCTAssertFalse(catalogue.figures(for: externalTable).contains { $0.namespace == "table" })
        } else { XCTAssertTrue(false, "Missing external-table reference passage") }

        func firstTableHTML(_ id: String) throws -> String? {
            guard let figure = catalogue.diagrams.first(where: { $0.id == id }),
                  let asset = figure.assets.first(where: { $0.kind == "table" }),
                  let url = catalogue.assetURL(asset, root: root) else {
                XCTAssertTrue(false, "Missing source table \(id)")
                return nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        func matches(_ pattern: String, in text: String) throws -> [String] {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        func cells(_ row: String) throws -> [String] {
            try matches("<(?:th|td)\\b[^>]*>(.*?)</(?:th|td)>", in: row).map {
                $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let html = try firstTableHTML("microeconomics-1.8a") {
            let rows = try matches("<tr\\b[^>]*>(.*?)</tr>", in: html)
            XCTAssertEqual(rows.count, 16)
            if rows.count >= 2 {
                XCTAssertEqual(try cells(rows[0]), ["Labour input (number of farmers)", "Grain output (kg)", "Average product of labour (kg/farmer)"])
                XCTAssertEqual(try cells(rows[1]), ["200", "171,000", "855"])
            }
        }
        if let html = try firstTableHTML("microeconomics-2.2c") {
            let headers = try matches("(<th\\b[^>]*\\bcolspan=[\"']3[\"'][^>]*>.*?</th>)", in: html)
            XCTAssertTrue(headers.contains { $0.contains("Complete specialization and trade") })
        }
        if let html = try firstTableHTML("microeconomics-8.5") {
            let cells = try matches("(<td\\b[^>]*\\browspan=[\"']2[\"'][^>]*>.*?</td>)", in: html)
            XCTAssertTrue(cells.contains { $0.contains("Market for a differentiated product, e.g. Cheerios") })
            XCTAssertTrue(cells.contains { $0.contains("Market in competitive equilibrium, e.g. a second-hand textbook") })
        }
        if let balanceSheets = catalogue.diagrams.first(where: { $0.id == "macroeconomics-6.3a" }) {
            XCTAssertEqual(balanceSheets.assets.count, 2)
            if balanceSheets.assets.count == 2 {
                for asset in balanceSheets.assets { XCTAssertEqual(asset.kind, "table") }
                if let before = catalogue.assetURL(balanceSheets.assets[0], root: root),
                   let after = catalogue.assetURL(balanceSheets.assets[1], root: root) {
                    let beforeHTML = try String(contentsOf: before, encoding: .utf8)
                    let afterHTML = try String(contentsOf: after, encoding: .utf8)
                    XCTAssertTrue(beforeHTML.contains("Before the loan"))
                    XCTAssertTrue(afterHTML.contains("After the loan"))
                    XCTAssertTrue(afterHTML.contains("Loan to Julia"))
                } else { XCTAssertTrue(false, "Missing before/after balance-sheet files") }
            }
        } else { XCTAssertTrue(false, "Missing source balance-sheet figure 6.3a") }
        for figure in tableFigures {
            XCTAssertTrue(["figure", "table"].contains(figure.namespace), figure.id)
            for asset in figure.assets where asset.kind == "table" {
                XCTAssertTrue(asset.path.hasPrefix("Tables/"), figure.id)
                XCTAssertTrue(asset.path.hasSuffix(".html"), figure.id)
                if let url = catalogue.assetURL(asset, root: root) {
                    let html = try String(contentsOf: url, encoding: .utf8)
                    XCTAssertTrue(html.contains("<table"), asset.path)
                    XCTAssertFalse(html.range(of: "<script\\b|<iframe\\b|<img\\b|<link\\b|<form\\b|<[a-z][^>]*\\son[a-z]+\\s*=", options: .regularExpression) != nil, asset.path)
                } else { XCTAssertTrue(false, "Missing bundled table \(asset.path)") }
            }
        }
    }

    func testActualDiagramCatalogueHasValidPassagesAndOfflineAssets() throws {
        let root = diagramResourceRoot
        let catalogue = try JSONDecoder().decode(FigureCatalogue.self, from: Data(contentsOf: root.appendingPathComponent("Diagram-Catalog.json")))
        let lib = try loadLibrary()
        let passages = Dictionary(uniqueKeysWithValues: lib.passages.map { ($0.id, $0) })
        let figureIDs = Set(catalogue.diagrams.map(\.id))
        XCTAssertFalse(catalogue.diagrams.isEmpty)
        XCTAssertFalse(catalogue.passageFigures.isEmpty)
        XCTAssertEqual(figureIDs.count, catalogue.diagrams.count)
        if let reference = passages["CORE Micro U01 S01 P006"] {
            XCTAssertTrue(catalogue.figures(for: reference).contains { $0.id == "microeconomics-1.1" })
        } else { XCTAssertTrue(false, "Missing known source passage CORE Micro U01 S01 P006") }
        if let reference = passages["CORE Micro U01 S01 P001"] {
            XCTAssertTrue(catalogue.figures(for: reference).isEmpty)
        } else { XCTAssertTrue(false, "Missing known source passage CORE Micro U01 S01 P001") }
        if let photograph = passages["CORE Macro U09 S01 P006"] {
            XCTAssertFalse(catalogue.figures(for: photograph).contains { $0.id == "macroeconomics-9.1" })
        } else { XCTAssertTrue(false, "Missing known photograph-reference passage") }
        if let reference = passages["CORE Macro U10 S02 P030"] {
            let ids = catalogue.figures(for: reference).map(\.id)
            XCTAssertTrue(ids.contains("macroeconomics-10.2"))
            XCTAssertTrue(ids.contains("microeconomics-1.1"))
            XCTAssertTrue(catalogue.explicitCrossBookReferences[reference.id]?.contains("microeconomics-1.1") == true)
        } else { XCTAssertTrue(false, "Missing known source passage CORE Macro U10 S02 P030") }

        for figure in catalogue.diagrams {
            XCTAssertTrue(["microeconomics", "macroeconomics"].contains(figure.book), figure.id)
            XCTAssertTrue((1...10).contains(figure.unit), figure.id)
            XCTAssertFalse(figure.number.isEmpty, figure.id)
            XCTAssertFalse(figure.caption.isEmpty, figure.id)
            XCTAssertTrue(URL(string: figure.source)?.scheme == "https", figure.id)
            XCTAssertFalse(figure.assets.isEmpty, figure.id)
            for asset in figure.assets {
                XCTAssertTrue(["image", "table"].contains(asset.kind), figure.id)
                XCTAssertFalse(asset.label.isEmpty, figure.id)
                XCTAssertTrue(URL(string: asset.source)?.scheme == "https", figure.id)
                let url = catalogue.assetURL(asset, root: root)
                XCTAssertTrue(url != nil, "\(figure.id): \(asset.path)")
                if let url { XCTAssertFalse(try Data(contentsOf: url).isEmpty, asset.path) }
            }
        }
        for (passageID, references) in catalogue.passageFigures {
            XCTAssertFalse(references.isEmpty, passageID)
            XCTAssertEqual(Set(references).count, references.count, passageID)
            guard let passage = passages[passageID] else {
                XCTAssertTrue(false, "Unknown passage \(passageID)")
                continue
            }
            XCTAssertTrue(references.allSatisfy { figureIDs.contains($0) }, passageID)
            let figures = catalogue.figures(for: passage)
            XCTAssertEqual(figures.map(\.id), references, passageID)
            let explicitCrossBook = Set(catalogue.explicitCrossBookReferences[passageID] ?? [])
            XCTAssertTrue(figures.allSatisfy { $0.book == passage.book || explicitCrossBook.contains($0.id) }, passageID)
        }
        for (passageID, explicitIDs) in catalogue.explicitCrossBookReferences {
            XCTAssertFalse(explicitIDs.isEmpty, passageID)
            XCTAssertTrue(Set(explicitIDs).isSubset(of: Set(catalogue.passageFigures[passageID] ?? [])), passageID)
            if let passage = passages[passageID] {
                for id in explicitIDs {
                    let figure = catalogue.diagrams.first { $0.id == id }
                    XCTAssertTrue(figure != nil, id)
                    if let figure { XCTAssertNotEqual(figure.book, passage.book, passageID) }
                }
            } else { XCTAssertTrue(false, "Unknown cross-book passage \(passageID)") }
        }
        let unmapped = lib.passages.first { catalogue.passageFigures[$0.id] == nil }
        XCTAssertTrue(unmapped != nil)
        if let unmapped { XCTAssertTrue(catalogue.figures(for: unmapped).isEmpty) }
    }
}
