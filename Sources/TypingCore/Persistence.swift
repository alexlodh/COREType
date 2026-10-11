import Foundation

public struct Preferences: Codable {
    public var selectedSections: Set<String> = []
    public var selectedPassageIDs: Set<String> = []
    public var mode: TestMode = .passage
    public var duration = 60
    public var order: PassagePicker.Order = .ordered
    public var flexiblePunctuation = true
    public var fontSize = 23.0
    public var bookFilter = "all"
    public var showTextbookMedia = true
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case selectedSections, selectedPassageIDs, mode, duration, order, flexiblePunctuation, fontSize, bookFilter, showTextbookMedia
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedSections = try values.decode(Set<String>.self, forKey: .selectedSections)
        selectedPassageIDs = try values.decodeIfPresent(Set<String>.self, forKey: .selectedPassageIDs) ?? []
        mode = try values.decode(TestMode.self, forKey: .mode)
        duration = try values.decode(Int.self, forKey: .duration)
        order = try values.decode(PassagePicker.Order.self, forKey: .order)
        flexiblePunctuation = try values.decode(Bool.self, forKey: .flexiblePunctuation)
        fontSize = try values.decode(Double.self, forKey: .fontSize)
        bookFilter = try values.decode(String.self, forKey: .bookFilter)
        showTextbookMedia = try values.decodeIfPresent(Bool.self, forKey: .showTextbookMedia) ?? true
    }
}
public struct TestResult: Codable, Identifiable {
    public let id: UUID
    public let date: Date
    public let passageID: String
    public let label: String
    public let book: String
    public let mode: TestMode
    public let duration: Int
    public let paragraphCount: Int
    public let reason: String
    public let metrics: Metrics
    public var completed: Bool { reason == "Passage complete" || reason == "Timer complete" }
    public init(id: UUID, date: Date, passageID: String, label: String, book: String, mode: TestMode, duration: Int, paragraphCount: Int, reason: String, metrics: Metrics) {
        self.id=id; self.date=date; self.passageID=passageID; self.label=label; self.book=book
        self.mode=mode; self.duration=duration; self.paragraphCount=paragraphCount; self.reason=reason; self.metrics=metrics
    }
}
public struct SavedState: Codable {
    public var preferences: Preferences
    public var results: [TestResult]
    public init(preferences: Preferences = Preferences(), results: [TestResult] = []) { self.preferences=preferences; self.results=results }
}
public struct StateFile {
    public let url: URL
    public init(url: URL) { self.url=url }
    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
