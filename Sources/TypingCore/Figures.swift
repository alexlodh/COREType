import Foundation

public struct FigureAsset: Codable, Equatable {
    public let path: String
    public let label: String
    public let source: String
    public let alt: String
    public let kind: String
    public init(path: String, label: String, source: String, alt: String = "", kind: String = "image") {
        self.path = path; self.label = label; self.source = source; self.alt = alt; self.kind = kind
    }
    enum CodingKeys: String, CodingKey { case path, label, source, alt, kind }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        path = try values.decode(String.self, forKey: .path)
        label = try values.decode(String.self, forKey: .label)
        source = try values.decode(String.self, forKey: .source)
        alt = try values.decode(String.self, forKey: .alt)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "image"
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
    public let namespace: String
    public var isTable: Bool { !assets.isEmpty && assets.allSatisfy { $0.kind == "table" } }
    public init(id: String, book: String, unit: Int, number: String, caption: String,
                source: String, attribution: String = "", assets: [FigureAsset], namespace: String = "figure") {
        self.id = id; self.book = book; self.unit = unit; self.number = number
        self.caption = caption; self.source = source; self.attribution = attribution; self.assets = assets; self.namespace = namespace
    }
    enum CodingKeys: String, CodingKey { case id, book, unit, number, caption, source, attribution, assets, namespace }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        book = try values.decode(String.self, forKey: .book)
        unit = try values.decode(Int.self, forKey: .unit)
        number = try values.decode(String.self, forKey: .number)
        caption = try values.decode(String.self, forKey: .caption)
        source = try values.decode(String.self, forKey: .source)
        attribution = try values.decode(String.self, forKey: .attribution)
        assets = try values.decode([FigureAsset].self, forKey: .assets)
        namespace = try values.decodeIfPresent(String.self, forKey: .namespace) ?? "figure"
    }
}

/// Source-proven associations are imported separately so the prepared text stays unchanged.
public struct FigureCatalogue: Codable {
    public let diagrams: [TextbookFigure]
    public let passageFigures: [String: [String]]
    public let explicitCrossBookReferences: [String: [String]]
    private let figuresByID: [String: TextbookFigure]
    public init(diagrams: [TextbookFigure] = [], passageFigures: [String: [String]] = [:], explicitCrossBookReferences: [String: [String]] = [:]) {
        self.diagrams = diagrams; self.passageFigures = passageFigures; self.explicitCrossBookReferences = explicitCrossBookReferences
        figuresByID = Dictionary(diagrams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    enum CodingKeys: String, CodingKey { case diagrams, passageFigures, explicitCrossBookReferences }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        diagrams = try values.decode([TextbookFigure].self, forKey: .diagrams)
        passageFigures = try values.decode([String: [String]].self, forKey: .passageFigures)
        explicitCrossBookReferences = try values.decodeIfPresent([String: [String]].self, forKey: .explicitCrossBookReferences) ?? [:]
        figuresByID = Dictionary(diagrams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    public func figures(for passage: Passage) -> [TextbookFigure] {
        let references = passageFigures[passage.id] ?? []
        var seen = Set<String>()
        return references.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            // A cross-book association requires explicit evidence in the imported catalogue.
            guard let figure = figuresByID[id], figure.book == passage.book || (explicitCrossBookReferences[passage.id] ?? []).contains(id) else { return nil }
            return figure
        }
    }
    /// Only the corresponding local image or table resource is allowed in the typing document.
    public func assetURL(_ asset: FigureAsset, root: URL) -> URL? {
        let folder: String
        let extensions: Set<String>
        switch asset.kind {
        case "image": folder = "Diagrams"; extensions = ["svg", "png", "jpg", "jpeg"]
        case "table": folder = "Tables"; extensions = ["html"]
        default: return nil
        }
        guard root.isFileURL, asset.path.hasPrefix(folder + "/"), extensions.contains(URL(fileURLWithPath: asset.path).pathExtension.lowercased()),
              !asset.path.split(separator: "/").contains("..") else { return nil }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let base = resolvedRoot.appendingPathComponent(folder, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let url = root.appendingPathComponent(asset.path).resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard base.path.hasPrefix(resolvedRoot.path + "/"), url.path.hasPrefix(base.path + "/"),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return nil }
        return url
    }
}
