import SwiftUI
import TypingCore

struct PracticeSnapshot {
    var passage: Passage?
    var engine: TypingEngine?
    var passageRevision: UInt64 = 0
    var inputRevision: UInt64 = 0
    var mediaRevision: UInt64 = 0
    var figures: [TextbookFigure] = []
    var focusToken = 0
    var focused = false
}

/// Only the practice content observes input/phase/focus changes. The coordinator's
/// sidebar, history and navigation do not subscribe to these frequent updates.
@MainActor final class PracticeDisplay: ObservableObject {
    @Published var snapshot = PracticeSnapshot()
}

/// Ten-Hz clock updates notify only the metric strip, never the typing document.
@MainActor final class MetricsDisplay: ObservableObject {
    @Published private(set) var metrics = Metrics(elapsed: 0, wpm: 0, rawWPM: 0, accuracy: 100,
                                                errorRate: 0, attempts: 0, mistakes: 0, corrected: 0,
                                                uncorrected: 0, correctCharacters: 0)
    func update(_ value: Metrics) {
        guard value != metrics else { return }
        metrics = value
    }
}

struct HistorySummary {
    var completed: [TestResult] = []
    var averageWPM: Double = 0
    var bestWPM: Double = 0
    var recentWPM: [Double] = []

    init(results: [TestResult] = []) {
        completed = results.filter(\.completed)
        averageWPM = completed.isEmpty ? 0 : completed.reduce(0) { $0 + $1.metrics.wpm } / Double(completed.count)
        bestWPM = completed.reduce(0) { max($0, $1.metrics.wpm) }
        recentWPM = completed.prefix(25).reversed().map { $0.metrics.wpm }
    }
}
