import Foundation

/// Explicit diagnostic runs only. Normal releases never collect or write counters.
@MainActor enum PerformanceCounters {
    private static let output: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--performance-report"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()
    static var enabled: Bool { output != nil }
    private static var counts: [String: Int] = [:]
    static func record(_ name: String, amount: Int = 1) {
        guard enabled else { return }
        counts[name, default: 0] += amount
    }
    static func flush() {
        guard let output else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: counts, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
        } catch { fputs("COREType performance report: \(error.localizedDescription)\n", stderr) }
    }
}
