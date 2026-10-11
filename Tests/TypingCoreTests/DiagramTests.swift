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
