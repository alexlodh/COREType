import Foundation
import TypingCore

private struct DeterministicRandom {
    var state: UInt64
    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

/// Intentionally scans retained input, independently of the production counters.
private struct ReferenceTypingEngine {
    var phase: Phase = .ready
    var target: [Character]
    var input: [Character] = []
    var attempts = 0, mistakes = 0, corrected = 0, completedParagraphs = 0
    var finishReason: String?
    let mode: TestMode
    let duration: Double
    let flexiblePunctuation: Bool
    var accrued = 0.0
    var started: Double?
    var finishedCorrect = 0, finishedErrors = 0

    init(text: String, mode: TestMode, duration: Double, flexiblePunctuation: Bool) {
        target = Array(text); self.mode = mode; self.duration = min(3600, max(1, duration))
        self.flexiblePunctuation = flexiblePunctuation
    }
    func matches(_ typed: Character, _ expected: Character) -> Bool {
        if typed == expected { return true }
        guard flexiblePunctuation else { return false }
        let groups = [Set<Character>("'‘’"), Set<Character>("\"“”"), Set<Character>("-–—"), Set<Character>(" \u{00a0}")]
        return groups.contains { $0.contains(typed) && $0.contains(expected) }
    }
    func elapsed(at now: Double) -> Double {
        let value = accrued + (started.map { max(0, now - $0) } ?? 0)
        return mode == .timed ? min(duration, value) : value
    }
    func metrics(at now: Double) -> Metrics {
        let currentCorrect = input.enumerated().filter { matches($0.element, target[$0.offset]) }.count
        let correct = finishedCorrect + currentCorrect
        let errors = finishedErrors + input.count - currentCorrect
        let elapsed = elapsed(at: now), minutes = elapsed / 60
        let accuracy = attempts == 0 ? 100 : Double(attempts - mistakes) / Double(attempts) * 100
        return Metrics(elapsed: elapsed, wpm: minutes > 0 ? Double(correct) / 5 / minutes : 0,
                       rawWPM: minutes > 0 ? Double(attempts) / 5 / minutes : 0,
                       accuracy: accuracy, errorRate: 100 - accuracy, attempts: attempts,
                       mistakes: mistakes, corrected: corrected, uncorrected: errors, correctCharacters: correct)
    }
    @discardableResult mutating func type(_ char: Character, at now: Double) -> Bool {
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
    mutating func advance(to text: String) {
        guard mode == .timed, phase == .running, input.count == target.count else { return }
        let correct = input.enumerated().filter { matches($0.element, target[$0.offset]) }.count
        finishedCorrect += correct; finishedErrors += input.count - correct
        target = Array(text); input = []
    }
    mutating func backspace(word: Bool, at now: Double) {
        tick(at: now)
        guard phase == .running, !input.isEmpty else { return }
        repeat {
            let index = input.count - 1
            if !matches(input[index], target[index]) { corrected += 1 }
            input.removeLast()
        } while word && !input.isEmpty && input.last != " "
    }
    mutating func tick(at now: Double) {
        if phase == .running && mode == .timed && elapsed(at: now) >= duration {
            accrued = duration; started = nil; phase = .finished; finishReason = "Timer complete"
        }
    }
    mutating func pause(at now: Double) {
        tick(at: now)
        guard phase == .running else { return }
        accrued = elapsed(at: now); started = nil; phase = .paused
    }
    mutating func resume(at now: Double) {
        guard phase == .paused else { return }
        phase = .running; started = now
    }
    mutating func finish(at now: Double, reason: String) {
        guard phase != .finished else { return }
        accrued = elapsed(at: now); started = nil; phase = .finished; finishReason = reason
    }
}

extension TypingCoreTests {
    func testIncrementalMetricsMatchDeterministicScanningReference() {
        let texts = ["ab", "one two three", "‘“—\u{00a0}’”–", "e\u{301}👩🏽‍💻𐐀 café", "a b c d e", ""]
        let characters = Array("abc xyz'‘’\"“”-–—\u{00a0}.…e\u{301}👩🏽‍💻𐐀")
        for seed in 1...80 {
            var random = DeterministicRandom(state: UInt64(seed))
            var now = 100.0
            var mode: TestMode = seed % 2 == 0 ? .timed : .passage
            var duration = Double([1, 2, 6, 60][seed % 4])
            var flexible = seed % 3 != 0
            var text = texts[random.next(texts.count)]
            var engine = TypingEngine(text: text, mode: mode, duration: duration, flexiblePunctuation: flexible)
            var reference = ReferenceTypingEngine(text: text, mode: mode, duration: duration, flexiblePunctuation: flexible)
            for step in 0..<300 {
                now += Double(random.next(40)) / 100
                let context = "seed \(seed), step \(step)"
                switch random.next(14) {
                case 0...5:
                    let character = engine.input.count < engine.target.count && random.next(2) == 0
                        ? engine.target[engine.input.count] : characters[random.next(characters.count)]
                    XCTAssertEqual(engine.type(character, at: now), reference.type(character, at: now), context)
                case 6, 7:
                    let word = random.next(2) == 0
                    engine.backspace(word: word, at: now); reference.backspace(word: word, at: now)
                case 8:
                    engine.pause(at: now); reference.pause(at: now)
                case 9:
                    engine.resume(at: now); reference.resume(at: now)
                case 10:
                    engine.tick(at: now); reference.tick(at: now)
                case 11:
                    text = texts[random.next(texts.count)]
                    engine.advance(to: text); reference.advance(to: text)
                case 12:
                    engine.finish(at: now, reason: "Interrupted"); reference.finish(at: now, reason: "Interrupted")
                default:
                    mode = random.next(2) == 0 ? .timed : .passage
                    duration = Double([1, 2, 6, 60][random.next(4)])
                    flexible = random.next(2) == 0; text = texts[random.next(texts.count)]
                    engine = TypingEngine(text: text, mode: mode, duration: duration, flexiblePunctuation: flexible)
                    reference = ReferenceTypingEngine(text: text, mode: mode, duration: duration, flexiblePunctuation: flexible)
                }
                XCTAssertEqual(engine.phase, reference.phase, context)
                XCTAssertEqual(engine.target, reference.target, context)
                XCTAssertEqual(engine.input, reference.input, context)
                XCTAssertEqual(engine.completedParagraphs, reference.completedParagraphs, context)
                XCTAssertEqual(engine.finishReason, reference.finishReason, context)
                XCTAssertEqual(engine.metrics(at: now), reference.metrics(at: now), context)
            }
        }
        // Keep these sessions active for thousands of real edits, rather than
        // letting random pause/finish operations dominate the counter checks.
        let activeText = "a e\u{301} 👩🏽‍💻 𐐀 ‘quoted’—words\u{00a0}and more text. "
        for seed in 1...32 {
            var random = DeterministicRandom(state: UInt64(seed) * 7919)
            var engine = TypingEngine(text: activeText, mode: .timed, duration: 3600)
            var reference = ReferenceTypingEngine(text: activeText, mode: .timed, duration: 3600, flexiblePunctuation: true)
            for step in 0..<600 {
                let now = Double(step) / 10
                if random.next(12) < 9 {
                    let character = random.next(3) == 0 ? characters[random.next(characters.count)] : engine.target[engine.input.count]
                    let complete = engine.type(character, at: now)
                    XCTAssertEqual(complete, reference.type(character, at: now))
                    if complete { engine.advance(to: activeText); reference.advance(to: activeText) }
                } else {
                    let word = random.next(5) == 0
                    engine.backspace(word: word, at: now); reference.backspace(word: word, at: now)
                }
                XCTAssertEqual(engine.input, reference.input)
                XCTAssertEqual(engine.metrics(at: now), reference.metrics(at: now), "active seed \(seed), step \(step)")
            }
        }
    }

    func testPunctuationMappingPreservesExactEquivalenceRelation() {
        let candidates = Array("'‘’\"“”-–— \u{00a0}.…‐‑−\t\n«»`´aé") + [Character("e\u{301}"), "👩🏽‍💻", "𐐀"]
        for flexible in [false, true] {
            let engine = TypingEngine(text: "", mode: .passage, flexiblePunctuation: flexible)
            let reference = ReferenceTypingEngine(text: "", mode: .passage, duration: 60, flexiblePunctuation: flexible)
            for typed in candidates {
                for expected in candidates {
                    XCTAssertEqual(engine.matches(typed, expected), reference.matches(typed, expected), "\(typed) / \(expected)")
                }
            }
        }
    }

    func testRevisionsIgnoreClockAndBlockedInputAndRecognizeRepeatedTarget() {
        var engine = TypingEngine(text: "ab", mode: .timed, duration: 10)
        XCTAssertEqual(engine.targetRevision, 0); XCTAssertEqual(engine.inputRevision, 0)
        engine.tick(at: 90); engine.pause(at: 90); engine.resume(at: 90)
        XCTAssertEqual(engine.inputRevision, 0)
        engine.type("a", at: 100); engine.type("x", at: 101)
        XCTAssertEqual(engine.inputRevision, 2)
        engine.type("z", at: 102)
        XCTAssertEqual(engine.inputRevision, 2)
        engine.advance(to: "ab")
        XCTAssertEqual(engine.targetRevision, 1); XCTAssertEqual(engine.inputRevision, 3)
        XCTAssertEqual(engine.metrics(at: 102).correctCharacters, 1)
        XCTAssertEqual(engine.metrics(at: 102).uncorrected, 1)
        engine.type("x", at: 103); engine.backspace(at: 104)
        XCTAssertEqual(engine.inputRevision, 5)
        engine.backspace(at: 105); engine.pause(at: 105); engine.resume(at: 106)
        XCTAssertEqual(engine.inputRevision, 5)
        engine.type("a", at: 107); engine.type("b", at: 108); engine.advance(to: "ab")
        XCTAssertEqual(engine.targetRevision, 2); XCTAssertEqual(engine.inputRevision, 8)
        engine.tick(at: 111); engine.type("x", at: 112); engine.backspace(at: 113)
        XCTAssertEqual(engine.inputRevision, 8)
        XCTAssertEqual(engine.metrics(at: 113).corrected, 1)
        engine = TypingEngine(text: "ab", mode: .timed, duration: 10)
        XCTAssertEqual(engine.inputRevision, 0); XCTAssertEqual(engine.targetRevision, 0)
        XCTAssertEqual(engine.metrics(at: 200).attempts, 0)
    }

    func testDeadlineIsExactAcrossRepeatedPausesAndLateDeletion() {
        var engine = TypingEngine(text: "abcdefghij", mode: .timed, duration: 2)
        XCTAssertNil(engine.deadline)
        XCTAssertEqual(engine.remainingDuration(at: 100), 2)
        engine.type("a", at: 100)
        XCTAssertEqual(engine.deadline, 102)
        for index in 0..<5 {
            let pauseTime = 100 + Double(index) * 10 + Double(index + 1) * 0.25
            engine.pause(at: pauseTime)
            XCTAssertNil(engine.deadline)
            XCTAssertEqual(engine.remainingDuration(at: pauseTime + 9), 2 - Double(index + 1) * 0.25)
            engine.resume(at: pauseTime + 10)
            XCTAssertEqual(engine.deadline, 102 + Double(index + 1) * 10)
        }
        engine.backspace(at: 151.999)
        XCTAssertEqual(engine.phase, .running); XCTAssertEqual(engine.input.count, 0)
        engine.type("b", at: 152)
        XCTAssertEqual(engine.phase, .finished); XCTAssertEqual(engine.attempts, 1)
        XCTAssertEqual(engine.metrics(at: 1_000).elapsed, 2)
        XCTAssertNil(engine.deadline); XCTAssertEqual(engine.remainingDuration(at: 1_000), 0)

        var lateBackspace = TypingEngine(text: "abcd", mode: .timed, duration: 2)
        lateBackspace.type("x", at: 10); lateBackspace.backspace(word: true, at: 12)
        XCTAssertEqual(lateBackspace.phase, .finished); XCTAssertEqual(String(lateBackspace.input), "x")
        XCTAssertEqual(lateBackspace.metrics(at: 99).corrected, 0)
        let passage = TypingEngine(text: "a", mode: .passage)
        XCTAssertNil(passage.remainingDuration(at: 0)); XCTAssertNil(passage.deadline)
    }

    func testUTF16RangeMapMatchesFullDisplayedPassageThroughEdits() {
        let source = Array("a👩🏽‍💻e\u{301}‘ 𐐀—b")
        let engine = TypingEngine(text: String(source), mode: .timed)
        var map = PassageUTF16Map(target: source)
        var input: [Character] = []
        let sequences: [[Character]] = [
            ["é"], [Character("e\u{301}")], [],
            ["𐐀"], ["𐐀", "x"], ["𐐀", "x", "👩🏽‍💻"],
            ["𐐀", "x", "👩🏽‍💻", "'", " "], ["𐐀", "x"], [],
            Array("a👩🏽‍💻e\u{301}' 𐐀-b"), Array("a 👩🏽‍💻x👩🏽‍💻"), []
        ]
        for next in sequences {
            var prefix = 0
            while prefix < min(input.count, next.count),
                  String(input[prefix]).utf16.elementsEqual(String(next[prefix]).utf16) { prefix += 1 }
            let displayed = next.enumerated().map { index, typed in
                engine.matches(typed, source[index]) || typed == " " ? source[index] : typed
            }
            let oldDisplay = source.enumerated().map { index, expected -> Character in
                guard index < input.count else { return expected }
                return engine.matches(input[index], expected) || input[index] == " " ? expected : input[index]
            }
            let oldRange = map.range(in: prefix..<max(input.count, next.count))
            let oldPrefix = oldDisplay.prefix(prefix).reduce(0) { $0 + String($1).utf16.count }
            let oldLength = oldDisplay[prefix..<max(input.count, next.count)].reduce(0) { $0 + String($1).utf16.count }
            XCTAssertEqual(oldRange, NSRange(location: oldPrefix, length: oldLength))
            map.replaceTypedSuffix(from: prefix, displayed: Array(displayed.dropFirst(prefix)))
            input = next
            let fullDisplay = displayed + source.dropFirst(next.count)
            var offset = 0
            for (index, character) in fullDisplay.enumerated() {
                let length = String(character).utf16.count
                XCTAssertEqual(map.offset(at: index), offset)
                XCTAssertEqual(map.range(at: index), NSRange(location: offset, length: length))
                offset += length
            }
            XCTAssertEqual(map.offset(at: source.count), offset)
            XCTAssertEqual(map.utf16Count, offset); XCTAssertEqual(map.typedCount, next.count)
        }
        let empty = PassageUTF16Map(target: [])
        XCTAssertEqual(empty.utf16Count, 0); XCTAssertEqual(empty.range(in: 0..<0), NSRange(location: 0, length: 0))

        // Apply the same suffix edits to a UTF-16 string buffer, then compare
        // its complete contents and every range with a from-scratch renderer.
        let candidates = Array("ab ée\u{301}👩🏽‍💻𐐀'‘’\"“”—–-\u{00a0}")
        var random = DeterministicRandom(state: 20261011)
        var randomMap = PassageUTF16Map(target: source)
        var randomInput: [Character] = []
        let buffer = NSMutableString(string: String(source))
        for _ in 0..<1_000 {
            var next = randomInput
            switch random.next(4) {
            case 0:
                if next.count < source.count { next.append(candidates[random.next(candidates.count)]) }
            case 1:
                if !next.isEmpty { next.removeLast() }
            case 2:
                if !next.isEmpty { next[random.next(next.count)] = candidates[random.next(candidates.count)] }
            default:
                next = (0..<random.next(source.count + 1)).map { _ in candidates[random.next(candidates.count)] }
            }
            var prefix = 0
            while prefix < min(randomInput.count, next.count),
                  String(randomInput[prefix]).utf16.elementsEqual(String(next[prefix]).utf16) { prefix += 1 }
            let displayed = next.enumerated().map { index, typed in
                engine.matches(typed, source[index]) || typed == " " ? source[index] : typed
            }
            let changedEnd = max(randomInput.count, next.count)
            let replacement = displayed.dropFirst(prefix) + source[next.count..<changedEnd]
            buffer.replaceCharacters(in: randomMap.range(in: prefix..<changedEnd), with: String(replacement))
            randomMap.replaceTypedSuffix(from: prefix, displayed: Array(displayed.dropFirst(prefix)))
            randomInput = next
            let expected = displayed + source.dropFirst(next.count)
            XCTAssertEqual(Array((buffer as String).utf16), Array(String(expected).utf16))
            var offset = 0
            for (index, character) in expected.enumerated() {
                let length = String(character).utf16.count
                XCTAssertEqual(randomMap.range(at: index), NSRange(location: offset, length: length))
                offset += length
            }
            XCTAssertEqual(randomMap.utf16Count, offset)
        }
    }
}
