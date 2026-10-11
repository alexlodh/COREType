import AppKit
import SwiftUI
import TypingCore

@MainActor final class AppModel: ObservableObject {
    let library: Library
    let attribution: String
    let resourceRoot: URL
    let figureCatalogue: FigureCatalogue
    let stateFile: StateFile
    @Published var preferences: Preferences {
        didSet {
            if preferences.bookFilter != oldValue.bookFilter { refreshSearch() }
            if preferences.fontSize != oldValue.fontSize || preferences.showTextbookMedia != oldValue.showTextbookMedia { publishPractice() }
        }
    }
    @Published var selection: Set<String> { didSet { refreshSelectedCount() } }
    @Published var results: [TestResult] { didSet { historySummary = HistorySummary(results: results) } }
    private(set) var current: Passage?
    private(set) var engine: TypingEngine?
    private var now = ProcessInfo.processInfo.systemUptime
    @Published var page = "practice" { didSet { syncTimers() } }
    @Published var search = "" { didSet { refreshSearch() } }
    @Published var expanded: Set<String> = ["microeconomics-1"]
    private(set) var focusToken = 0
    var focused = false {
        didSet { if focused != oldValue { publishPractice(); syncTimers() } }
    }
    @Published var notice: String?
    @Published var showingSettings = false { didSet { syncTimers() } }
    @Published var showingInfo = false { didSet { syncTimers() } }
    let practiceDisplay = PracticeDisplay()
    let metricsDisplay = MetricsDisplay()
    private(set) var selectedCount = 0
    private(set) var visibleChapters: [Chapter] = []
    private(set) var currentFigures: [TextbookFigure] = []
    private(set) var historySummary = HistorySummary()
    private let sectionCounts: [String: Int]
    private let chapterSectionIDs: [String: Set<String>]
    private var passageRevision: UInt64 = 0
    private var inputRevision: UInt64 = 0
    private var mediaRevision: UInt64 = 0
    private var practiceVisible = false
    private var appliedSelection: Set<String>
    private var pool: [Passage] = []
    private var picker = PassagePicker()
    private var initial: Passage?
    private var sessionID = UUID()
    private var savedSession: UUID?
    private var displayTimer: Timer?
    private var deadlineTimer: Timer?
    private var scheduledDeadline: Double?
    private var observers: [NSObjectProtocol] = []
    private var persistenceEnabled = true

    init() {
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("library.json")
        let root = FileManager.default.fileExists(atPath: bundled.path) ? Bundle.main.resourceURL! : Bundle.module.resourceURL!.appendingPathComponent("Resources")
        var loadNotice: String?
        let passages: [Passage]
        do { passages = try JSONDecoder().decode([Passage].self, from: Data(contentsOf: root.appendingPathComponent("library.json"))) }
        catch { passages = []; loadNotice = "Could not load textbook library: \(error.localizedDescription)" }
        library = Library(passages: passages)
        sectionCounts = Dictionary(uniqueKeysWithValues: library.chapters.flatMap { $0.sections.map { ($0.id, $0.passages.count) } })
        chapterSectionIDs = Dictionary(uniqueKeysWithValues: library.chapters.map { ($0.id, Set($0.sections.map(\.id))) })
        resourceRoot = root
        do { figureCatalogue = try JSONDecoder().decode(FigureCatalogue.self, from: Data(contentsOf: root.appendingPathComponent("Diagram-Catalog.json"))) }
        catch { figureCatalogue = FigureCatalogue(); loadNotice = "Could not load textbook figures and tables: \(error.localizedDescription)" }
        attribution = (try? String(contentsOf: root.appendingPathComponent("Attribution.txt"), encoding: .utf8)) ?? "Attribution resource is unavailable."
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let directory = testing ? URL(fileURLWithPath: "/tmp/COREType-UI-Testing") : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("COREType")
        stateFile = StateFile(url: directory.appendingPathComponent("state.json"))
        var state = SavedState()
        if FileManager.default.fileExists(atPath: stateFile.url.path) {
            do { state = try stateFile.load() }
            catch {
                let backup = directory.appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                do { try FileManager.default.copyItem(at: stateFile.url, to: backup) }
                catch { persistenceEnabled = false }
                loadNotice = "Saved data could not be read. A preserved backup is kept in the data folder; this session uses fresh settings."
                state.preferences.selectedSections = library.sectionIDs
            }
        } else { state.preferences.selectedSections = library.sectionIDs }
        state.preferences.selectedSections.formIntersection(library.sectionIDs)
        state.preferences.duration = min(3600, max(1, state.preferences.duration))
        state.preferences.fontSize = min(32, max(18, state.preferences.fontSize))
        preferences = state.preferences; selection = state.preferences.selectedSections
        appliedSelection = state.preferences.selectedSections; results = state.results; notice = loadNotice
        refreshSelectedCount(); refreshSearch(); historySummary = HistorySummary(results: results)
        pool = library.scope(selection)
        let arguments = ProcessInfo.processInfo.arguments
        if testing, let flag = arguments.firstIndex(of: "--fixture"), arguments.indices.contains(flag + 1),
           let passage = library.passages.first(where: { $0.id == arguments[flag + 1] }) {
            // A repeatable native regression fixture is confined to the
            // isolated UI-testing profile and never changes normal app data.
            selection = [passage.sectionID]; appliedSelection = selection; preferences.selectedSections = selection
            pool = library.scope(selection); reset(to: passage)
        } else { loadNext() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncTimers() }
            })
        }
    }
    deinit {
        displayTimer?.invalidate(); deadlineTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    var activeCount: Int { pool.count }
    var pendingScope: Bool { selection != appliedSelection }
    var canGoPrevious: Bool { picker.canGoPrevious(order: preferences.order, in: pool) }
    var metrics: Metrics { metricsDisplay.metrics }
    var phase: Phase { engine?.phase ?? .ready }
    func sectionIDs(for chapter: Chapter) -> Set<String> { chapterSectionIDs[chapter.id] ?? [] }
    private func refreshSelectedCount() {
        PerformanceCounters.record("selectedCountRefreshes")
        selectedCount = selection.reduce(0) { $0 + (sectionCounts[$1] ?? 0) }
    }
    private func refreshSearch() {
        PerformanceCounters.record("searchRefreshes")
        visibleChapters = library.search(search, book: preferences.bookFilter)
    }
    private func refreshFigures() {
        PerformanceCounters.record("figureLookups")
        currentFigures = current.map { figureCatalogue.figures(for: $0) } ?? []
        passageRevision &+= 1; mediaRevision &+= 1
    }
    private func publishPractice() {
        practiceDisplay.snapshot = PracticeSnapshot(passage: current, engine: engine, passageRevision: passageRevision,
                                                    inputRevision: inputRevision, mediaRevision: mediaRevision,
                                                    figures: currentFigures, focusToken: focusToken, focused: focused)
    }
    private func refreshMetrics() {
        PerformanceCounters.record("metricsSnapshots")
        metricsDisplay.update(engine?.metrics(at: now) ?? Metrics(elapsed: 0, wpm: 0, rawWPM: 0, accuracy: 100,
                                                                errorRate: 0, attempts: 0, mistakes: 0, corrected: 0,
                                                                uncorrected: 0, correctCharacters: 0))
    }
    private func refreshPractice() { refreshMetrics(); publishPractice(); syncTimers() }
    func setPracticeVisible(_ visible: Bool) { practiceVisible = visible; syncTimers() }
    private func syncTimers() {
        let window = NSApp.keyWindow
        let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        let needsDisplay = PracticeTimerPolicy.needsDisplayTimer(phase: phase, practiceVisible: practiceVisible && page == "practice",
                                                                appActive: NSApp.isActive, keyWindowVisible: visible,
                                                                focused: focused, modalPresented: showingSettings || showingInfo)
        if needsDisplay && displayTimer == nil {
            // Both callbacks execute only on the main run loop. assumeIsolated
            // checks that guarantee without allocating a Task for every tick.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common); displayTimer = timer
            PerformanceCounters.record("displayTimerStarts")
        } else if !needsDisplay && displayTimer != nil {
            displayTimer?.invalidate(); displayTimer = nil
            PerformanceCounters.record("displayTimerStops")
        }
        let clock = ProcessInfo.processInfo.systemUptime
        let deadline = PracticeTimerPolicy.deadline(for: engine, at: clock)
        if let deadline, deadline == scheduledDeadline { return }
        deadlineTimer?.invalidate(); deadlineTimer = nil; scheduledDeadline = deadline
        guard let deadline else { return }
        let timer = Timer(timeInterval: max(0, deadline - clock), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.deadlineReached() }
        }
        // Completion has no cosmetic tolerance and remains responsive while
        // menus or scrollers put the run loop in event-tracking mode.
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common); deadlineTimer = timer
        PerformanceCounters.record("deadlineTimerSchedules")
    }
    private func deadlineReached() {
        PerformanceCounters.record("deadlineCallbacks")
        deadlineTimer = nil; scheduledDeadline = nil
        now = ProcessInfo.processInfo.systemUptime
        engine?.tick(at: now)
        refreshPractice(); saveFinished()
    }
    func save() {
        defer { PerformanceCounters.flush() }
        guard persistenceEnabled else { return }
        do {
            try stateFile.save(SavedState(preferences: preferences, results: Array(results.prefix(1000))))
            PerformanceCounters.record("stateWrites")
        }
        catch { notice = "Could not save locally: \(error.localizedDescription)" }
    }
    func toggleSection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    func toggleChapter(_ c: Chapter) {
        let ids = sectionIDs(for: c)
        if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }
    func selectVisible(_ enabled: Bool) {
        let ids = Set(visibleChapters.flatMap { $0.sections.map(\.id) })
        if enabled { selection.formUnion(ids) } else { selection.subtract(ids) }
    }
    func applyScope() {
        archive(reason: "Scope changed")
        appliedSelection = selection; preferences.selectedSections = selection
        pool = library.scope(selection); picker.reset(); loadNext(); save()
    }
    func configure(mode: TestMode? = nil, duration: Int? = nil, order: PassagePicker.Order? = nil, punctuation: Bool? = nil) {
        archive(reason: "Settings changed")
        if let mode { preferences.mode = mode }
        if let duration { preferences.duration = min(3600, max(1, duration)) }
        if let order { preferences.order = order; picker.reset() }
        if let punctuation { preferences.flexiblePunctuation = punctuation }
        if let current { reset(to: current) } else { loadNext() }
        save()
    }
    func bookFilter(_ value: String) { preferences.bookFilter = value; save() }
    func fontSize(_ value: Double) { preferences.fontSize = value; save() }
    func showTextbookMedia(_ enabled: Bool) { preferences.showTextbookMedia = enabled; save() }
    func reset(to passage: Passage) {
        picker.remember(passage)
        current = passage; initial = passage
        engine = TypingEngine(text: passage.text, mode: preferences.mode, duration: Double(preferences.duration), flexiblePunctuation: preferences.flexiblePunctuation)
        sessionID = UUID(); now = ProcessInfo.processInfo.systemUptime
        refreshFigures(); inputRevision &+= 1; focusToken += 1; refreshPractice()
    }
    func loadNext() {
        guard let p = picker.next(in: pool, order: preferences.order) else {
            current = nil; initial = nil; engine = nil; sessionID = UUID()
            refreshFigures(); inputRevision &+= 1; refreshPractice(); return
        }
        reset(to: p)
    }
    func next() { archive(reason: "Skipped"); page = "practice"; loadNext() }
    func previous() {
        guard canGoPrevious else { return }
        archive(reason: "Skipped"); page = "practice"
        if let passage = picker.previous(in: pool, order: preferences.order) { reset(to: passage) }
    }
    func restart() {
        archive(reason: "Restarted"); page = "practice"
        if let initial { reset(to: initial) }
    }
    func focus() { focusToken += 1; publishPractice() }
    func type(_ text: String) {
        guard page == "practice", engine != nil else { return }
        now = ProcessInfo.processInfo.systemUptime
        let oldCount = engine!.input.count, oldPhase = phase, oldPassageRevision = passageRevision
        for char in text where !char.isNewline && !char.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            let more = engine!.type(char, at: now)
            if more, let p = picker.next(in: pool, order: preferences.order) {
                current = p; engine!.advance(to: p.text); refreshFigures()
            }
        }
        if engine!.input.count != oldCount || passageRevision != oldPassageRevision {
            inputRevision &+= 1; refreshPractice()
        } else if phase != oldPhase { refreshPractice() }
        saveFinished()
    }
    func backspace(word: Bool) {
        guard page == "practice", let oldCount = engine?.input.count else { return }
        let oldPhase = phase
        now = ProcessInfo.processInfo.systemUptime; engine?.backspace(word: word, at: now)
        if engine?.input.count != oldCount { inputRevision &+= 1; refreshPractice() }
        else if phase != oldPhase { refreshPractice() }
        saveFinished()
    }
    func tick() {
        guard phase == .running else { return }
        PerformanceCounters.record("displayTicks")
        now = ProcessInfo.processInfo.systemUptime
        var updated = engine!
        updated.tick(at: now)
        if updated.phase != engine?.phase { engine = updated; refreshPractice() }
        else { refreshMetrics() }
        saveFinished()
    }
    func pause() {
        now = ProcessInfo.processInfo.systemUptime; engine?.pause(at: now)
        refreshPractice(); saveFinished()
        PerformanceCounters.flush()
    }
    func pauseOrResume() {
        now = ProcessInfo.processInfo.systemUptime
        if phase == .paused { engine?.resume(at: now); focusToken += 1; refreshPractice() } else { pause() }
    }
    func navigate(_ destination: String) {
        if destination != "practice" { pause() }
        page = destination; if destination == "practice" { focus() }
        PerformanceCounters.flush()
    }
    func saveFinished() { if phase == .finished { archive(reason: engine?.finishReason ?? "Finished") } }
    func archive(reason: String) {
        now = ProcessInfo.processInfo.systemUptime
        let oldPhase = phase
        engine?.tick(at: now)
        if phase != oldPhase { refreshPractice() }
        guard let engine, engine.attempts > 0, savedSession != sessionID, let initial else { return }
        let result = TestResult(id: sessionID, date: Date(), passageID: initial.id, label: initial.sectionTitle,
                                book: initial.bookTitle, mode: preferences.mode, duration: preferences.duration,
                                paragraphCount: engine.completedParagraphs, reason: engine.phase == .finished ? (engine.finishReason ?? reason) : reason, metrics: engine.metrics(at: now))
        results.insert(result, at: 0); if results.count > 1000 { results.removeLast(results.count - 1000) }
        savedSession = sessionID; save()
    }
    func replay(_ result: TestResult) {
        guard let p = library.passages.first(where: { $0.id == result.passageID }) else { return }
        archive(reason: "History replay")
        preferences.mode = result.mode; preferences.duration = result.duration
        selection = [p.sectionID]; appliedSelection = selection; preferences.selectedSections = selection
        pool = library.scope(selection); picker.reset(); reset(to: p); page = "practice"; save()
    }
    func exportHistory() {
        pause()
        let panel = NSSavePanel(); panel.nameFieldStringValue = "COREType-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let formatter = ISO8601DateFormatter()
        let header = "date,book,section,passage_id,mode,status,seconds,wpm,raw_wpm,accuracy,error_rate,attempts,mistakes,corrected,uncorrected\n"
        let rows = results.map { r in
            [quote(formatter.string(from: r.date)),quote(r.book),quote(r.label),quote(r.passageID),r.mode.rawValue,quote(r.reason),
             String(format: "%.2f", r.metrics.elapsed),String(format:"%.2f",r.metrics.wpm),String(format:"%.2f",r.metrics.rawWPM),
             String(format:"%.2f",r.metrics.accuracy),String(format:"%.2f",r.metrics.errorRate),String(r.metrics.attempts),
             String(r.metrics.mistakes),String(r.metrics.corrected),String(r.metrics.uncorrected)].joined(separator: ",")
        }.joined(separator: "\n")
        do { try (header + rows + "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { notice = "History export failed: \(error.localizedDescription)" }
    }
}
