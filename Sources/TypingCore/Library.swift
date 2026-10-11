import Foundation

public struct Passage: Codable, Identifiable, Equatable {
    public let id: String
    public let book: String
    public let unit: Int
    public let chapter: String
    public let section: Int
    public let sectionTitle: String
    public let paragraph: Int
    public let text: String
    public let source: String
    public var sectionID: String { "\(book)-\(unit)-\(section)" }
    public var chapterID: String { "\(book)-\(unit)" }
    public var bookTitle: String { book == "microeconomics" ? "Microeconomics" : "Macroeconomics" }
    public init(id: String, book: String, unit: Int, chapter: String, section: Int, sectionTitle: String, paragraph: Int, text: String, source: String) {
        self.id = id; self.book = book; self.unit = unit; self.chapter = chapter
        self.section = section; self.sectionTitle = sectionTitle; self.paragraph = paragraph
        self.text = text; self.source = source
    }
}

public struct Section: Identifiable {
    public let id: String
    public let title: String
    public let passages: [Passage]
}
public struct Chapter: Identifiable {
    public let id: String
    public let book: String
    public let unit: Int
    public let title: String
    public let sections: [Section]
    public var count: Int { sections.reduce(0) { $0 + $1.passages.count } }
}
public struct Library {
    public let passages: [Passage]
    public let chapters: [Chapter]
    public var sectionIDs: Set<String> { Set(passages.map(\.sectionID)) }
    public init(passages: [Passage]) {
        self.passages = passages.sorted(by: Self.precedes)
        let groups = Dictionary(grouping: self.passages, by: \.chapterID)
        self.chapters = groups.values.map { items in
            let p = items[0]
            let sections = Dictionary(grouping: items, by: \.sectionID).values.map { s in
                Section(id: s[0].sectionID, title: s[0].sectionTitle, passages: s.sorted(by: Self.precedes))
            }.sorted { $0.passages[0].section < $1.passages[0].section }
            return Chapter(id: p.chapterID, book: p.book, unit: p.unit, title: p.chapter, sections: sections)
        }.sorted { Self.precedes($0.sections[0].passages[0], $1.sections[0].passages[0]) }
    }
    public static func precedes(_ a: Passage, _ b: Passage) -> Bool {
        if a.book != b.book { return a.book == "microeconomics" }
        if a.unit != b.unit { return a.unit < b.unit }
        if a.section != b.section { return a.section < b.section }
        return a.paragraph < b.paragraph
    }
    public func scope(_ selection: Set<String>) -> [Passage] {
        passages.filter { selection.contains($0.sectionID) }
    }
    public func search(_ query: String, book: String = "all") -> [Chapter] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return chapters.compactMap { c in
            guard book == "all" || c.book == book else { return nil }
            let chapterMatch = query.isEmpty || "\(c.unit) \(c.title) \(c.book)".localizedCaseInsensitiveContains(query)
            let sections = chapterMatch ? c.sections : c.sections.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return sections.isEmpty ? nil : Chapter(id: c.id, book: c.book, unit: c.unit, title: c.title, sections: sections)
        }
    }
}

/// Order affects which whole excerpt is chosen, never the words inside it.
public struct PassagePicker {
    public enum Order: String, Codable, CaseIterable { case ordered, random }
    public private(set) var lastID: String?
    public init() {}
    public mutating func reset() { lastID = nil }
    public mutating func remember(_ passage: Passage) { lastID = passage.id }
    public mutating func next(in passages: [Passage], order: Order) -> Passage? {
        guard !passages.isEmpty else { lastID = nil; return nil }
        let choice: Passage
        if order == .ordered {
            if let index = passages.firstIndex(where: { $0.id == lastID }) { choice = passages[(index + 1) % passages.count] }
            else { choice = passages[0] }
        } else {
            let candidates = passages.count > 1 ? passages.filter { $0.id != lastID } : passages
            choice = candidates.randomElement()!
        }
        lastID = choice.id
        return choice
    }
}
