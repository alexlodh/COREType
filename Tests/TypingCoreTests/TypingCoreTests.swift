import Foundation
import TypingCore

final class TypingCoreTests {
    func testMetricsIncludeMistakesAfterCorrection() {
        var e = TypingEngine(text: "abcde", mode: .passage)
        e.type("a", at: 100); e.type("x", at: 110); e.backspace(at: 115)
        e.type("b", at: 120); e.type("c", at: 130); e.type("d", at: 140); e.type("e", at: 160)
        let m = e.metrics(at: 1000)
        XCTAssertEqual(e.phase, .finished)
        XCTAssertEqual(m.elapsed, 60)
        XCTAssertEqual(m.wpm, 1)
        XCTAssertEqual(m.rawWPM, 1.2, accuracy: 0.0001)
        XCTAssertEqual(m.accuracy, 100.0 * 5 / 6, accuracy: 0.0001)
        XCTAssertEqual(m.mistakes, 1); XCTAssertEqual(m.corrected, 1); XCTAssertEqual(m.uncorrected, 0)
    }
    func testUncorrectedErrorsReduceRetainedWPM() {
        var e = TypingEngine(text: "abcde", mode: .passage)
        for (i,c) in "axcye".enumerated() { e.type(c, at: Double(i) * 15) }
        let m = e.metrics(at: 60)
        XCTAssertEqual(m.wpm, 0.6); XCTAssertEqual(m.rawWPM, 1)
        XCTAssertEqual(m.accuracy, 60); XCTAssertEqual(m.errorRate, 40); XCTAssertEqual(m.uncorrected, 2)
        e.backspace(at: 61); e.type("f", at: 62)
        XCTAssertEqual(e.input.count, 5); XCTAssertEqual(e.attempts, 5)
    }
    func testTimerStartsOnFirstCharacterAndCompletesPrecisely() {
        var e = TypingEngine(text: "abcdefghij", mode: .timed, duration: 15)
        e.tick(at: 1000); XCTAssertEqual(e.phase, .ready)
        e.type("a", at: 1000); e.tick(at: 1014.999); XCTAssertEqual(e.phase, .running)
        e.type("b", at: 1020)
        XCTAssertEqual(e.phase, .finished); XCTAssertEqual(e.attempts, 1)
        XCTAssertEqual(e.metrics(at: 2000).elapsed, 15)
        XCTAssertEqual(e.finishReason, "Timer complete")
    }
    func testPauseExcludesTimeAndResumingKeepsInput() {
        var e = TypingEngine(text: "abcdefghij", mode: .timed, duration: 30)
        e.type("a", at: 10); e.pause(at: 20)
        e.tick(at: 500); e.type("x", at: 501)
        XCTAssertEqual(e.phase, .paused); XCTAssertEqual(e.metrics(at: 500).elapsed, 10)
        XCTAssertEqual(e.input, ["a"])
        e.resume(at: 600); e.type("b", at: 605); e.tick(at: 621)
        XCTAssertEqual(e.phase, .finished); XCTAssertEqual(e.metrics(at: 621).elapsed, 30)
        XCTAssertEqual(e.input, ["a", "b"])
    }
    func testTimedContinuationAccumulatesAcrossParagraphs() {
        var e = TypingEngine(text: "ab", mode: .timed, duration: 60)
        XCTAssertFalse(e.type("a", at: 0)); XCTAssertTrue(e.type("x", at: 10))
        e.advance(to: "cde")
        XCTAssertEqual(e.completedParagraphs, 1); XCTAssertEqual(e.input.count, 0)
        e.backspace(at: 11)
        e.type("c", at: 20); e.type("d", at: 30); e.tick(at: 60)
        let m = e.metrics(at: 70)
        XCTAssertEqual(m.correctCharacters, 3); XCTAssertEqual(m.uncorrected, 1)
        XCTAssertEqual(m.attempts, 4); XCTAssertEqual(m.wpm, 0.6)
    }
    func testPunctuationEquivalenceDoesNotAlterTarget() {
        var e = TypingEngine(text: "‘a’—b", mode: .passage)
        for (i,c) in "'a'-b".enumerated() { e.type(c, at: Double(i)) }
        XCTAssertEqual(e.metrics(at: 10).accuracy, 100)
        XCTAssertEqual(String(e.target), "‘a’—b")
        let strict = TypingEngine(text: "‘", mode: .passage, flexiblePunctuation: false)
        XCTAssertFalse(strict.matches("'", "‘")); XCTAssertFalse(e.matches(".", "…"))
    }
    func testUnicodeGraphemesAndWordBackspace() {
        var e = TypingEngine(text: "café hello", mode: .passage)
        for c in "café hxx" { e.type(c, at: 1) }
        e.backspace(word: true, at: 2)
        XCTAssertEqual(String(e.input), "café ")
        XCTAssertEqual(e.metrics(at: 2).corrected, 2)
        e.backspace(word: true, at: 3)
        XCTAssertTrue(e.input.isEmpty); XCTAssertEqual(e.attempts, 8)
    }
    func testIdleAndRepeatedTestsDoNotCarryMetrics() {
        var e = TypingEngine(text: "ab", mode: .passage)
        e.type("x", at: 10); e.pause(at: 11)
        e = TypingEngine(text: "ab", mode: .passage)
        XCTAssertEqual(e.phase, .ready); XCTAssertEqual(e.metrics(at: 100).elapsed, 0)
        XCTAssertEqual(e.attempts, 0); XCTAssertEqual(e.mistakes, 0)
        XCTAssertEqual(e.metrics(at: 100).accuracy, 100)
    }
    func loadLibrary() throws -> Library {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/COREType/Resources/library.json"))
        return Library(passages: try JSONDecoder().decode([Passage].self, from: data))
    }
    func testRealLibraryMappingAndFiltering() throws {
        let lib = try loadLibrary()
        XCTAssertEqual(lib.passages.count, 6893); XCTAssertEqual(lib.chapters.count, 20); XCTAssertEqual(lib.sectionIDs.count, 271)
        XCTAssertEqual(lib.passages.filter { $0.book == "microeconomics" }.count, 3505)
        XCTAssertEqual(lib.passages.filter { $0.book == "macroeconomics" }.count, 3388)
        let microFirst = lib.chapters[0]
        XCTAssertEqual(microFirst.unit, 1); XCTAssertEqual(microFirst.count, 295)
        XCTAssertEqual(lib.scope(["microeconomics-1-1"]).count, 7)
        XCTAssertTrue(lib.scope([]).isEmpty)
        XCTAssertEqual(lib.scope(["macroeconomics-1-1"]).first?.book, "macroeconomics")
        XCTAssertTrue(lib.search("inflation", book: "macroeconomics").allSatisfy { $0.book == "macroeconomics" })
        XCTAssertFalse(lib.search("Ibn Battuta").isEmpty)
        XCTAssertTrue(lib.search("no_such_topic_12345").isEmpty)
        for p in lib.passages {
            XCTAssertTrue(p.sectionTitle.hasPrefix("\(p.unit).\(p.section) "), p.id)
            XCTAssertFalse(p.chapter.isEmpty); XCTAssertFalse(p.text.isEmpty)
        }
    }
    func testOrderRandomScopeAndEmptySelection() throws {
        let lib = try loadLibrary(); let scope = lib.scope(["microeconomics-1-1"])
        var picker = PassagePicker()
        for p in scope { XCTAssertEqual(picker.next(in: scope, order: .ordered)?.id, p.id) }
        XCTAssertEqual(picker.next(in: scope, order: .ordered)?.id, scope[0].id)
        var prior: String?
        for _ in 0..<300 {
            let p = picker.next(in: scope, order: .random)!
            XCTAssertEqual(p.sectionID, "microeconomics-1-1"); XCTAssertNotEqual(p.id, prior); prior = p.id
        }
        XCTAssertNil(picker.next(in: [], order: .random))
        XCTAssertEqual(picker.next(in: [scope[0]], order: .random)?.id, scope[0].id)
        XCTAssertEqual(picker.next(in: [scope[0]], order: .random)?.id, scope[0].id)
    }
    func testLongestPassageIsCompleteAndNotTruncated() throws {
        let lib = try loadLibrary(); let p = lib.passages.max { $0.text.count < $1.text.count }!
        XCTAssertTrue(p.text.count > 900)
        var e = TypingEngine(text: p.text, mode: .passage)
        for (i,c) in p.text.enumerated() { e.type(c, at: Double(i) * 0.1) }
        XCTAssertEqual(e.phase, .finished); XCTAssertEqual(e.input.count, p.text.count)
        XCTAssertEqual(e.metrics(at: 1000).accuracy, 100); XCTAssertEqual(e.completedParagraphs, 1)
    }
    func testSettingsHistoryAtomicRoundTripAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StateFile(url: directory.appendingPathComponent("state.json"))
        XCTAssertTrue(try file.load().results.isEmpty)
        var state = SavedState(); state.preferences.selectedSections = ["microeconomics-1-1"]
        state.preferences.duration=23; state.preferences.mode = .timed; state.preferences.order = .random; state.preferences.fontSize=27
        var e = TypingEngine(text: "abcde", mode: .passage)
        for (i,c) in "abcde".enumerated() { e.type(c, at: Double(i)*15) }
        state.results = [TestResult(id: UUID(), date: Date(), passageID: "test", label: "section", book: "Microeconomics", mode: .passage, duration: 23, paragraphCount: 1, reason: "Passage complete", metrics: e.metrics(at: 60))]
        try file.save(state); let restored = try file.load()
        XCTAssertEqual(restored.preferences.selectedSections, state.preferences.selectedSections)
        XCTAssertEqual(restored.preferences.duration, 23); XCTAssertEqual(restored.preferences.order, .random)
        XCTAssertEqual(restored.results[0].metrics, state.results[0].metrics)
        state.preferences.selectedSections = []; try file.save(state)
        XCTAssertTrue(try file.load().preferences.selectedSections.isEmpty)
        try Data("invalid".utf8).write(to: file.url)
        XCTAssertThrowsError(try file.load())
    }

    func testTextbookMediaPreferenceMigratesWithoutResettingSettingsOrHistory() throws {
        XCTAssertTrue(Preferences().showTextbookMedia)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("COREType-preference-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StateFile(url: directory.appendingPathComponent("state.json"))
        XCTAssertTrue(try file.load().preferences.showTextbookMedia)

        var preferences = Preferences()
        preferences.selectedSections = ["microeconomics-1-6", "macroeconomics-6-3"]
        preferences.mode = .timed
        preferences.duration = 47
        preferences.order = .random
        preferences.flexiblePunctuation = false
        preferences.fontSize = 29
        preferences.bookFilter = "macroeconomics"
        var engine = TypingEngine(text: "abcde", mode: .passage)
        engine.type("x", at: 0)
        engine.backspace(at: 1)
        for (index, character) in "abcde".enumerated() { engine.type(character, at: Double(index) * 15 + 2) }
        let result = TestResult(id: UUID(uuidString: "11335577-2244-6688-AAAA-BBCCDDEEFF00")!,
                                date: Date(timeIntervalSince1970: 1_793_318_400),
                                passageID: "CORE Micro U01 S06 P008", label: "1.6 A model of production",
                                book: "Microeconomics", mode: .passage, duration: 47,
                                paragraphCount: 1, reason: "Passage complete", metrics: engine.metrics(at: 62))
        let state = SavedState(preferences: preferences, results: [result])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Release 1.2 stored every existing field but had no inline-media
        // setting. Loading it must add the default without resetting a scope,
        // custom duration, punctuation choice, or any saved result.
        var legacyObject = try JSONSerialization.jsonObject(with: encoder.encode(state)) as! [String: Any]
        var legacyPreferences = legacyObject["preferences"] as! [String: Any]
        legacyPreferences.removeValue(forKey: "showTextbookMedia")
        legacyObject["preferences"] = legacyPreferences
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys]).write(to: file.url)

        var restored = try file.load()
        XCTAssertTrue(restored.preferences.showTextbookMedia)
        XCTAssertEqual(restored.preferences.selectedSections, preferences.selectedSections)
        XCTAssertEqual(restored.preferences.mode, preferences.mode)
        XCTAssertEqual(restored.preferences.duration, preferences.duration)
        XCTAssertEqual(restored.preferences.order, preferences.order)
        XCTAssertEqual(restored.preferences.flexiblePunctuation, preferences.flexiblePunctuation)
        XCTAssertEqual(restored.preferences.fontSize, preferences.fontSize)
        XCTAssertEqual(restored.preferences.bookFilter, preferences.bookFilter)
        XCTAssertEqual(try encoder.encode(restored.results), try encoder.encode(state.results))

        // The user's opt-out survives a disk round trip and affects only its
        // preference field; history, including corrected mistakes, is exact.
        restored.preferences.showTextbookMedia = false
        try file.save(restored)
        let optedOut = try file.load()
        XCTAssertFalse(optedOut.preferences.showTextbookMedia)
        XCTAssertEqual(try encoder.encode(optedOut.results), try encoder.encode(state.results))
        var afterPreferences = try JSONSerialization.jsonObject(with: encoder.encode(optedOut.preferences)) as! [String: Any]
        afterPreferences.removeValue(forKey: "showTextbookMedia")
        // JSONEncoder does not define iteration order for a Set.
        afterPreferences["selectedSections"] = optedOut.preferences.selectedSections.sorted()
        legacyPreferences["selectedSections"] = preferences.selectedSections.sorted()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: afterPreferences, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: legacyPreferences, options: [.sortedKeys]))

        // Invalid present values remain errors, rather than silently restoring
        // defaults and discarding the user's saved state.
        legacyPreferences["showTextbookMedia"] = "off"
        legacyObject["preferences"] = legacyPreferences
        XCTAssertThrowsError(try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: legacyObject)))
    }
}
