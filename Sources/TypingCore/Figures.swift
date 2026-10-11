import Foundation

public struct FigureAsset: Codable, Equatable {
    public let path: String
    public let label: String
    public let source: String
    public let alt: String
    public init(path: String, label: String, source: String, alt: String = "") {
        self.path = path; self.label = label; self.source = source; self.alt = alt
    }
}

public struct TextbookFigure: Codable, Identifiable, Equatable {
    public let id: String
    public let book: String
    public let unit: Int
    public let number: String
    public let caption: String
    public let source: String
    public let attribution: String
    public let assets: [FigureAsset]
    public init(id: String, book: String, unit: Int, number: String, caption: String,
                source: String, attribution: String = "", assets: [FigureAsset]) {
        self.id = id; self.book = book; self.unit = unit; self.number = number
        self.caption = caption; self.source = source; self.attribution = attribution; self.assets = assets
    }
}

/// Source-proven associations are imported separately so the prepared text stays unchanged.
public struct FigureCatalogue: Codable {
    public let diagrams: [TextbookFigure]
    public let passageFigures: [String: [String]]
    public let explicitCrossBookReferences: [String: [String]]
    public init(diagrams: [TextbookFigure] = [], passageFigures: [String: [String]] = [:], explicitCrossBookReferences: [String: [String]] = [:]) {
        self.diagrams = diagrams; self.passageFigures = passageFigures; self.explicitCrossBookReferences = explicitCrossBookReferences
    }
    enum CodingKeys: String, CodingKey { case diagrams, passageFigures, explicitCrossBookReferences }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        diagrams = try values.decode([TextbookFigure].self, forKey: .diagrams)
        passageFigures = try values.decode([String: [String]].self, forKey: .passageFigures)
        explicitCrossBookReferences = try values.decodeIfPresent([String: [String]].self, forKey: .explicitCrossBookReferences) ?? [:]
    }
    public func figures(for passage: Passage) -> [TextbookFigure] {
        let references = passageFigures[passage.id] ?? []
        var seen = Set<String>()
        return references.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            // A cross-book association requires explicit evidence in the imported catalogue.
            return diagrams.first { $0.id == id && ($0.book == passage.book || (explicitCrossBookReferences[passage.id] ?? []).contains(id)) }
        }
    }
    /// Only local, bundled diagram files are allowed in the viewer.
    public func assetURL(_ asset: FigureAsset, root: URL) -> URL? {
        guard root.isFileURL, asset.path.hasPrefix("Diagrams/"),
              !asset.path.split(separator: "/").contains("..") else { return nil }
        let base = root.appendingPathComponent("Diagrams", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let url = root.appendingPathComponent(asset.path).resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard url.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return nil }
        return url
    }
}
