import AppKit
import SwiftUI
import Darwin
import TypingCore

/// An isolated controller for exercising the real production AppKit renderer.
/// It never opens a window or reads/writes the normal or UI-testing profile.
@MainActor final class AppModel: ObservableObject {
    var engine: TypingEngine?
    var preferences = Preferences()
    var currentFigures: [TextbookFigure] = []
    let figureCatalogue: FigureCatalogue
    let resourceRoot: URL
    var focusToken = 0
    var page = "practice"
    var focused = false
    init(root: URL, catalogue: FigureCatalogue) {
        resourceRoot = root; figureCatalogue = catalogue
        preferences.showTextbookMedia = false; preferences.fontSize = 23
    }
    func type(_ text: String) {}
    func backspace(word: Bool) {}
    func pauseOrResume() {}
    func next() {}
}

@MainActor final class RendererHarness {
    let model: AppModel
    let scroll: NSScrollView
    var passageRevision: UInt64 = 1
    var inputRevision: UInt64 = 1
    init(root: URL, catalogue: FigureCatalogue, engine: TypingEngine) {
        model = AppModel(root: root, catalogue: catalogue); model.engine = engine
#if OPTIMIZED
        let surface = TypingSurface(model: model, engine: engine, passageRevision: passageRevision,
                                    inputRevision: inputRevision, fontSize: model.preferences.fontSize,
                                    figures: [], mediaRevision: 1, showTextbookMedia: false,
                                    focusToken: 0, page: "practice")
#else
        let surface = TypingSurface(model: model)
#endif
        scroll = surface.benchmarkMakeNSView()
        scroll.frame = NSRect(x: 0, y: 0, width: 960, height: 480)
        scroll.layoutSubtreeIfNeeded()
        update()
    }
    func update() {
#if OPTIMIZED
        let surface = TypingSurface(model: model, engine: model.engine!, passageRevision: passageRevision,
                                    inputRevision: inputRevision, fontSize: model.preferences.fontSize,
                                    figures: model.currentFigures, mediaRevision: passageRevision,
                                    showTextbookMedia: model.preferences.showTextbookMedia,
                                    focusToken: 0, page: "practice")
#else
        let surface = TypingSurface(model: model)
#endif
        surface.benchmarkUpdateNSView(scroll)
    }
    var textView: PassageTextView { (scroll.documentView as! PassageDocumentView).textView }
}

@MainActor func referenceDisplay(_ engine: TypingEngine, fontSize: Double) -> (NSAttributedString, Int) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 8; paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [.font: Typography.passageFont(size: fontSize),
        .foregroundColor: Palette.untypedColor, .paragraphStyle: paragraph]
    let display = NSMutableAttributedString(string: "")
    var caret = 0
    for (index, expected) in engine.target.enumerated() {
        let typed = index < engine.input.count ? engine.input[index] : nil
        let correct = typed.map { engine.matches($0, expected) } ?? false
        let character = typed != nil && !correct && typed != " " ? typed! : expected
        let piece = NSMutableAttributedString(string: String(character), attributes: attributes)
        if typed != nil {
            piece.addAttribute(.foregroundColor, value: correct ? Palette.textColor : Palette.errorColor,
                               range: NSRange(location: 0, length: piece.length))
            if !correct {
                piece.addAttribute(.backgroundColor, value: NSColor(red: 0.8, green: 0.2, blue: 0.28, alpha: 0.17),
                                   range: NSRange(location: 0, length: piece.length))
                piece.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                   range: NSRange(location: 0, length: piece.length))
            }
        }
        display.append(piece)
        if index < engine.input.count { caret += piece.length }
    }
    // NSTextStorage fixes unsupported glyph fonts (for example Arial to
    // AppleColorEmoji) during editing. Give the full rebuild reference the
    // same AppKit fixup before comparing every attribute at every UTF-16 unit.
    let reference = NSTextStorage(attributedString: display)
    reference.fixAttributes(in: NSRange(location: 0, length: reference.length))
    return (reference, caret)
}

@MainActor func checkRenderer(root: URL, catalogue: FigureCatalogue) throws -> Int {
    let passages = ["a 😀 e\u{301} 👨‍👩‍👧‍👦 ‘quote’ — space\u{00a0}fin", "é \"word\" – 🧠 end", "short"]
    let wrong: [Character] = ["x", " ", "😀", "é", "e\u{301}", "👨‍👩‍👧‍👦", "\u{00a0}", "'", "-"]
    var engine = TypingEngine(text: passages[0], mode: .timed, duration: 3600)
    let harness = RendererHarness(root: root, catalogue: catalogue, engine: engine)
    var seed: UInt64 = 0x434F524554797065
    var assertions = 0
    var now = 0.0
    func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
    func verify(_ label: String) throws {
        let (expected, caret) = referenceDisplay(engine, fontSize: harness.model.preferences.fontSize)
        let storage = harness.textView.textStorage!
        guard storage.string.utf16.elementsEqual(expected.string.utf16), storage.length == expected.length,
              harness.textView.caretOffset == caret else {
            throw NSError(domain: "RendererBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Display or UTF-16 caret mismatch after \(label)"])
        }
        assertions += 3
        for offset in 0..<storage.length {
            let actual = storage.attributes(at: offset, effectiveRange: nil)
            let reference = expected.attributes(at: offset, effectiveRange: nil)
            guard NSDictionary(dictionary: actual).isEqual(to: reference) else {
                throw NSError(domain: "RendererBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "Attributes mismatch after \(label), UTF-16 offset \(offset): actual \(actual); reference \(reference)"])
            }
            assertions += 1
        }
        // A repeated snapshot is a no-op and must preserve exact encodings.
        harness.update()
        guard storage.string.utf16.elementsEqual(expected.string.utf16), harness.textView.caretOffset == caret else {
            throw NSError(domain: "RendererBenchmark", code: 3, userInfo: [NSLocalizedDescriptionKey: "Repeated update changed text"])
        }
        assertions += 2
    }
    func updateAndVerify(_ label: String) throws {
        harness.inputRevision &+= 1; harness.model.engine = engine; harness.update()
        try verify(label)
    }
    // Canonically equal wrong Characters can have different UTF-16 lengths.
    // Batch each deletion/retype into one snapshot so prefix fallbacks are used.
    engine = TypingEngine(text: "x x x", mode: .timed, duration: 3600)
    harness.passageRevision &+= 1
    try updateAndVerify("Unicode fixture reset")
    engine.type("é", at: now)
    try updateAndVerify("wrong precomposed accent")
    engine.backspace(at: now); engine.type(Character("e\u{301}"), at: now)
    try updateAndVerify("batched precomposed to decomposed wrong glyph")
    engine.backspace(at: now); engine.type("👩🏽‍💻", at: now)
    try updateAndVerify("batched combining to emoji ZWJ glyph")
    engine.type(" ", at: now); engine.type("𐐀", at: now)
    try updateAndVerify("batched correct space and non-BMP wrong glyph")
    engine.backspace(word: true, at: now)
    try updateAndVerify("word deletion restores the source UTF-16 ranges")
    engine.backspace(word: true, at: now)
    engine.type(" ", at: now)
    try updateAndVerify("wrong space displays the expected source glyph")
    engine = TypingEngine(text: "‘—\u{00a0}“x’", mode: .timed, duration: 3600)
    harness.passageRevision &+= 1
    for character in "'- \"x'" { engine.type(character, at: now) }
    try updateAndVerify("equivalent punctuation displays original source glyphs")
    engine = TypingEngine(text: passages[0], mode: .timed, duration: 3600)
    harness.passageRevision &+= 1
    try updateAndVerify("randomized fixture reset")
    for step in 0..<1600 {
        now += 0.01
        if engine.input.count == engine.target.count {
            engine.advance(to: passages[step % passages.count]); harness.passageRevision &+= 1
        }
        let choice = next() % 10
        if choice < 3 { engine.backspace(word: choice == 0, at: now) }
        else if engine.input.count < engine.target.count {
            let typed = choice < 6 ? wrong[Int(next() % UInt64(wrong.count))] : engine.target[engine.input.count]
            engine.type(typed, at: now)
        }
        if step % 67 == 0 { engine.pause(at: now); engine.resume(at: now + 0.001) }
        if step % 43 == 0 { harness.model.preferences.fontSize = Double(20 + step % 3) }
        try updateAndVerify("randomized operation \(step)")
    }
    return assertions
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
        Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}

@main struct RendererBenchmark {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        func value(_ flag: String, _ fallback: String) -> String {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return fallback }
            return args[index + 1]
        }
        let root = URL(fileURLWithPath: value("--resources", "Sources/COREType/Resources"))
        let catalogue = try JSONDecoder().decode(FigureCatalogue.self, from: Data(contentsOf: root.appendingPathComponent("Diagram-Catalog.json")))
        if args.contains("--check") {
            let assertions = try checkRenderer(root: root, catalogue: catalogue)
            PerformanceCounters.flush()
            let report: [String: Any] = ["renderer_assertions": assertions, "failures": 0, "operations": 1600]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: value("--output", "/tmp/COREType-renderer-check.json")), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return
        }
        let passages = try JSONDecoder().decode([Passage].self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
        let passage = passages.first { $0.id == value("--passage", "CORE Macro U08 S09 P012") }!
        let seconds = Double(value("--seconds", "30"))!
        let runs = Int(value("--runs", "3"))!
        var windows: [[String: Any]] = []
        for run in 1...runs {
            var engine = TypingEngine(text: passage.text, mode: .timed, duration: 3600)
            let harness = RendererHarness(root: root, catalogue: catalogue, engine: engine)
            // Run-loop and initial text/WebKit setup are excluded from steady CPU.
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            let started = ProcessInfo.processInfo.systemUptime
            let initialCPU = cpuSeconds()
            var latency: [Double] = []
            let ticks = Int(seconds * 10)
            var inputEvents = 0
            for tick in 1...ticks {
                let deadline = started + Double(tick) / 10
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { RunLoop.main.run(until: Date().addingTimeInterval(remaining)) }
                let now = ProcessInfo.processInfo.systemUptime
                engine.tick(at: now)
                _ = engine.metrics(at: now)
                if tick % 2 == 0 {
                    let before = ProcessInfo.processInfo.systemUptime
                    inputEvents += 1
                    if inputEvents % 23 == 0 { engine.backspace(at: now) }
                    else if engine.input.count < engine.target.count {
                        let typed: Character = inputEvents % 17 == 0 ? "😀" : engine.target[engine.input.count]
                        engine.type(typed, at: now)
                    }
                    harness.inputRevision &+= 1; harness.model.engine = engine
                    harness.update()
                    latency.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
                }
#if !OPTIMIZED
                if tick % 2 != 0 { harness.model.engine = engine; harness.update() }
#endif
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let cpu = cpuSeconds() - initialCPU
            let sorted = latency.sorted()
            let window: [String: Any] = ["run": run, "elapsed_seconds": elapsed, "cpu_seconds": cpu,
                "average_cpu_percent": 100 * cpu / elapsed, "input_events": inputEvents,
                "median_renderer_update_ms": sorted[sorted.count / 2],
                "p95_renderer_update_ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                "maximum_renderer_update_ms": sorted.last!]
            windows.append(window)
            let data = try JSONSerialization.data(withJSONObject: window, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        }
        PerformanceCounters.flush()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let report: [String: Any] = ["method": "unattached production AppKit renderer; monotonic wall time and cumulative getrusage CPU",
            "limitations": "No native window, visual drawing, caret blink, SwiftUI body evaluation, or attributed WebKit-helper CPU; renderer update latency is not end-to-end input latency",
            "cpu_convention": "100 percent is one logical core", "passage": passage.id,
            "passage_characters": passage.text.count, "viewport": "960x480", "font_size": 23,
            "media_enabled": false, "input_events_per_second": 5, "metrics_refreshes_per_second": 10,
            "warmup_seconds_per_run": 2, "counter_scope": "all setup and active windows; CPU and latency exclude setup/warm-up",
            "peak_resident_bytes_including_setup": usage.ru_maxrss, "windows": windows]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: value("--output", "/tmp/COREType-renderer-benchmark.json")), options: .atomic)
    }
}
