import Foundation

public enum TestMode: String, Codable, CaseIterable { case passage, timed }
public enum Phase: String, Codable { case ready, running, paused, finished }
public struct Metrics: Codable, Equatable {
    public var elapsed: Double
    public var wpm: Double
    public var rawWPM: Double
    public var accuracy: Double
    public var errorRate: Double
    public var attempts: Int
    public var mistakes: Int
    public var corrected: Int
    public var uncorrected: Int
    public var correctCharacters: Int
    public init(elapsed: Double, wpm: Double, rawWPM: Double, accuracy: Double, errorRate: Double, attempts: Int, mistakes: Int, corrected: Int, uncorrected: Int, correctCharacters: Int) {
        self.elapsed=elapsed; self.wpm=wpm; self.rawWPM=rawWPM; self.accuracy=accuracy; self.errorRate=errorRate
        self.attempts=attempts; self.mistakes=mistakes; self.corrected=corrected; self.uncorrected=uncorrected; self.correctCharacters=correctCharacters
    }
}

/// All counts are extended grapheme clusters. Clock arguments are monotonic seconds.
public struct TypingEngine {
    public private(set) var phase: Phase = .ready
    public private(set) var target: [Character]
    public private(set) var input: [Character] = []
    public private(set) var attempts = 0
    public private(set) var mistakes = 0
    public private(set) var corrected = 0
    public private(set) var completedParagraphs = 0
    public private(set) var finishReason: String?
    public let mode: TestMode
    public let duration: Double
    public let flexiblePunctuation: Bool
    private var accrued: Double = 0
    private var started: Double?
    private var finishedCorrect = 0
    private var finishedErrors = 0
    public init(text: String, mode: TestMode, duration: Double = 60, flexiblePunctuation: Bool = true) {
        target = Array(text); self.mode = mode; self.duration = min(3600, max(1, duration))
        self.flexiblePunctuation = flexiblePunctuation
    }
    public func matches(_ typed: Character, _ expected: Character) -> Bool {
        if typed == expected { return true }
        guard flexiblePunctuation else { return false }
        let groups = [Set<Character>("'‘’"), Set<Character>("\"“”"), Set<Character>("-–—"), Set<Character>(" \u{00a0}")]
        return groups.contains { $0.contains(typed) && $0.contains(expected) }
    }
    public func elapsed(at now: Double) -> Double {
        let result = accrued + (started.map { max(0, now - $0) } ?? 0)
        return mode == .timed ? min(duration, result) : result
    }
    public func metrics(at now: Double) -> Metrics {
        let correct = finishedCorrect + input.enumerated().filter { matches($0.element, target[$0.offset]) }.count
        let errors = finishedErrors + input.count - (correct - finishedCorrect)
        let elapsed = elapsed(at: now)
        let minutes = elapsed / 60
        let accuracy = attempts == 0 ? 100 : Double(attempts - mistakes) / Double(attempts) * 100
        return Metrics(elapsed: elapsed, wpm: minutes > 0 ? Double(correct) / 5 / minutes : 0,
                       rawWPM: minutes > 0 ? Double(attempts) / 5 / minutes : 0,
                       accuracy: accuracy, errorRate: 100 - accuracy, attempts: attempts,
                       mistakes: mistakes, corrected: corrected, uncorrected: errors, correctCharacters: correct)
    }
    /// Returns true when a timed test needs the next whole paragraph.
    @discardableResult public mutating func type(_ char: Character, at now: Double) -> Bool {
        tick(at: now)
        guard phase == .ready || phase == .running, input.count < target.count else { return false }
        if phase == .ready { phase = .running; started = now }
        attempts += 1
        if !matches(char, target[input.count]) { mistakes += 1 }
        input.append(char)
        if input.count == target.count {
            completedParagraphs += 1
            if mode == .passage { finish(at: now, reason: "Passage complete") }
            else { return true }
        }
        return false
    }
    public mutating func advance(to text: String) {
        guard mode == .timed, phase == .running, input.count == target.count else { return }
        let correct = input.enumerated().filter { matches($0.element, target[$0.offset]) }.count
        finishedCorrect += correct; finishedErrors += input.count - correct
        target = Array(text); input = []
    }
    public mutating func backspace(word: Bool = false, at now: Double) {
        tick(at: now)
        guard phase == .running, !input.isEmpty else { return }
        repeat {
            let index = input.count - 1
            if !matches(input[index], target[index]) { corrected += 1 }
            input.removeLast()
        } while word && !input.isEmpty && input.last != " "
    }
    public mutating func tick(at now: Double) {
        if phase == .running && mode == .timed && elapsed(at: now) >= duration {
            accrued = duration; started = nil; phase = .finished; finishReason = "Timer complete"
        }
    }
    public mutating func pause(at now: Double) {
        tick(at: now)
        guard phase == .running else { return }
        accrued = elapsed(at: now); started = nil; phase = .paused
    }
    public mutating func resume(at now: Double) {
        guard phase == .paused else { return }
        phase = .running; started = now
    }
    public mutating func finish(at now: Double, reason: String) {
        guard phase != .finished else { return }
        accrued = elapsed(at: now); started = nil; phase = .finished; finishReason = reason
    }
}
