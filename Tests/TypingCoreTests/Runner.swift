import Foundation

// Dependency-free test runner, so the Command Line Tools alone can run the suite.
private var failures = 0
private var assertions = 0
func check(_ value: Bool, _ message: String, file: StaticString, line: UInt) {
    assertions += 1
    if !value { failures += 1; print("FAIL \(file):\(line) \(message)") }
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a == b, "\(a) != \(b) \(message)", file: file, line: line) }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a != b, "Unexpected equality \(message)", file: file, line: line) }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { check(abs(a-b) <= accuracy, "\(a) != \(b) ± \(accuracy)", file: file, line: line) }
func XCTAssertTrue(_ a: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { check(a, "Expected true \(message)", file: file, line: line) }
func XCTAssertFalse(_ a: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { check(!a, "Expected false \(message)", file: file, line: line) }
func XCTAssertNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) { check(a == nil, "Expected nil", file: file, line: line) }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); check(false, "Expected an error", file: file, line: line) }
    catch { check(true, "", file: file, line: line) }
}
@main struct Runner {
    static func main() {
        let tests = TypingCoreTests()
        let cases: [(String, () throws -> Void)] = [
            ("metric calculation and corrected mistakes", tests.testMetricsIncludeMistakesAfterCorrection),
            ("uncorrected errors and completion lock", tests.testUncorrectedErrorsReduceRetainedWPM),
            ("precise timer completion", tests.testTimerStartsOnFirstCharacterAndCompletesPrecisely),
            ("pause, interruption, and resume", tests.testPauseExcludesTimeAndResumingKeepsInput),
            ("timed paragraph continuation", tests.testTimedContinuationAccumulatesAcrossParagraphs),
            ("punctuation equivalence and source preservation", tests.testPunctuationEquivalenceDoesNotAlterTarget),
            ("Unicode and word backspace", tests.testUnicodeGraphemesAndWordBackspace),
            ("repeat resets statistics", tests.testIdleAndRepeatedTestsDoNotCarryMetrics),
            ("real-library chapter mapping, search, and filtering", tests.testRealLibraryMappingAndFiltering),
            ("ordered, random, singleton, and empty scopes", tests.testOrderRandomScopeAndEmptySelection),
            ("longest complete passage", tests.testLongestPassageIsCompleteAndNotTruncated),
            ("settings/history persistence and corrupt data", tests.testSettingsHistoryAtomicRoundTripAndCorruption),
            ("source-proven diagram matching and book isolation", tests.testDiagramMatchingUsesProvenAssociationsAndBookIsolation),
            ("local diagram assets and invalid-path rejection", tests.testDiagramAssetsRemainInsideLocalBundle),
            ("real diagram catalogue and offline resources", tests.testActualDiagramCatalogueHasValidPassagesAndOfflineAssets)
        ]
        for (name, action) in cases {
            let prior = failures
            do { try action() } catch { failures += 1; print("FAIL \(name): \(error)") }
            print("\(failures == prior ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) checks, \(assertions) assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
}
