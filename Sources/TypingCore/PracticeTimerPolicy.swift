import Foundation

/// Cosmetic display updates are independent of the monotonic test deadline.
/// Keeping the policy pure makes every lifecycle transition deterministic to test.
public enum PracticeTimerPolicy {
    public static func needsDisplayTimer(phase: Phase, practiceVisible: Bool, appActive: Bool,
                                         keyWindowVisible: Bool, focused: Bool, modalPresented: Bool) -> Bool {
        phase == .running && practiceVisible && appActive && keyWindowVisible && focused && !modalPresented
    }

    /// This deadline remains scheduled even if the display is temporarily hidden
    /// or loses keyboard focus. Pausing the engine cancels it; resuming creates
    /// the deadline from the remaining active time, never from timer tick counts.
    public static func deadline(for engine: TypingEngine?, at now: Double) -> Double? {
        // The engine retains the original deadline even when `now` is later.
        // Reconstructing it from capped elapsed time would move an overdue
        // deadline forward to the query time.
        engine?.deadline
    }
}
