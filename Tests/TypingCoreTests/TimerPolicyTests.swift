import Foundation
import TypingCore

extension TypingCoreTests {
    func testCosmeticTimerPolicyRequiresVisibleActiveFocusedRunningPractice() {
        for phase in [Phase.ready, .running, .paused, .finished] {
            for flags in 0..<32 {
                let visible = flags & 1 != 0, active = flags & 2 != 0
                let key = flags & 4 != 0, focused = flags & 8 != 0, modal = flags & 16 != 0
                XCTAssertEqual(PracticeTimerPolicy.needsDisplayTimer(phase: phase, practiceVisible: visible, appActive: active,
                                                                     keyWindowVisible: key, focused: focused, modalPresented: modal),
                               phase == .running && visible && active && key && focused && !modal)
            }
        }
    }

    func testTimedDeadlineSurvivesDisplaySuppressionAndRepeatedPauseResume() {
        var engine = TypingEngine(text: "abcdefghijklmnopqrstuvwxyz", mode: .timed, duration: 2)
        XCTAssertNil(PracticeTimerPolicy.deadline(for: engine, at: 10))
        engine.type("a", at: 10)
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 10)!, 12)
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 10.4)!, 12, accuracy: 0.000001)
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 15)!, 12, accuracy: 0.000001)
        // A hidden/unfocused display cancels only the cosmetic timer.
        XCTAssertFalse(PracticeTimerPolicy.needsDisplayTimer(phase: engine.phase, practiceVisible: false, appActive: true,
                                                             keyWindowVisible: false, focused: false, modalPresented: false))
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 10.4)!, 12, accuracy: 0.000001)
        engine.pause(at: 10.5)
        XCTAssertNil(PracticeTimerPolicy.deadline(for: engine, at: 999))
        engine.resume(at: 1000)
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 1000)!, 1001.5)
        engine.pause(at: 1000.25); engine.resume(at: 2000)
        XCTAssertEqual(PracticeTimerPolicy.deadline(for: engine, at: 2000)!, 2001.25)
        engine.tick(at: 2001.249)
        XCTAssertEqual(engine.phase, .running)
        // A delayed callback uses the monotonic deadline; late input cannot
        // create an attempt, correction, or extra active time.
        engine.backspace(at: 2005)
        engine.type("b", at: 2006)
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.input, ["a"]); XCTAssertEqual(engine.attempts, 1)
        XCTAssertEqual(engine.metrics(at: 9000).elapsed, 2)
        XCTAssertNil(PracticeTimerPolicy.deadline(for: engine, at: 9000))
        XCTAssertNil(PracticeTimerPolicy.deadline(for: TypingEngine(text: "ab", mode: .passage), at: 0))
    }
}
