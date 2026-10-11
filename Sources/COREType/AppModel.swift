import AppKit
import SwiftUI
import TypingCore

@MainActor final class AppModel: ObservableObject {
    let library: Library
    let attribution: String
    let resourceRoot: URL
    let figureCatalogue: FigureCatalogue
    let stateFile: StateFile
    @Published var preferences: Preferences
    @Published var selection: Set<String>
    @Published var results: [TestResult]
    @Published var current: Passage?
    @Published var engine: TypingEngine?
    @Published var now = ProcessInfo.processInfo.systemUptime
    @Published var page = "practice"
    @Published var search = ""
    @Published var expanded: Set<String> = ["microeconomics-1"]
    @Published var focusToken = 0
    @Published var focused = false
    @Published var notice: String?
    @Published var showingSettings = false
    @Published var showingInfo = false
    @Published var showingFigures = false
    private var appliedSelection: Set<String>
    private var pool: [Passage] = []
    private var picker = PassagePicker()
    private var initial: Passage?
    private var sessionID = UUID()
    private var savedSession: UUID?
    private var timer: Timer?
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
        resourceRoot = root
        do { figureCatalogue = try JSONDecoder().decode(FigureCatalogue.self, from: Data(contentsOf: root.appendingPathComponent("Diagram-Catalog.json"))) }
        catch { figureCatalogue = FigureCatalogue(); loadNotice = "Could not load textbook diagrams: \(error.localizedDescription)" }
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
        pool = library.scope(selection)
        loadNext()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.archive(reason: "App closed"); self?.save() }
        })
    }
    var selectedCount: Int { library.scope(selection).count }
    var activeCount: Int { pool.count }
    var pendingScope: Bool { selection != appliedSelection }
    var visibleChapters: [Chapter] { library.search(search, book: preferences.bookFilter) }
    var metrics: Metrics { engine?.metrics(at: now) ?? Metrics(elapsed: 0, wpm: 0, rawWPM: 0, accuracy: 100, errorRate: 0, attempts: 0, mistakes: 0, corrected: 0, uncorrected: 0, correctCharacters: 0) }
    var phase: Phase { engine?.phase ?? .ready }
    var currentFigures: [TextbookFigure] { current.map { figureCatalogue.figures(for: $0) } ?? [] }
    func showFigures() { pause(); showingFigures = true }
    func save() {
        guard persistenceEnabled else { return }
        do { try stateFile.save(SavedState(preferences: preferences, results: Array(results.prefix(1000)))) }
        catch { notice = "Could not save locally: \(error.localizedDescription)" }
    }
    func toggleSection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    func toggleChapter(_ c: Chapter) {
        let fullChapter = library.chapters.first { $0.id == c.id } ?? c
        let ids = Set(fullChapter.sections.map(\.id))
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
    func reset(to passage: Passage) {
        picker.remember(passage)
        current = passage; initial = passage
        engine = TypingEngine(text: passage.text, mode: preferences.mode, duration: Double(preferences.duration), flexiblePunctuation: preferences.flexiblePunctuation)
        sessionID = UUID(); now = ProcessInfo.processInfo.systemUptime; focus()
    }
    func loadNext() {
        guard let p = picker.next(in: pool, order: preferences.order) else {
            current = nil; initial = nil; engine = nil; sessionID = UUID(); return
        }
        reset(to: p)
    }
    func next() { archive(reason: "Skipped"); page = "practice"; loadNext() }
    func restart() {
        archive(reason: "Restarted"); page = "practice"
        if let initial { reset(to: initial) }
    }
    func focus() { focusToken += 1 }
    func type(_ text: String) {
        guard page == "practice", !showingFigures, engine != nil else { return }
        now = ProcessInfo.processInfo.systemUptime
        for char in text where !char.isNewline && !char.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            let more = engine!.type(char, at: now)
            if more, let p = picker.next(in: pool, order: preferences.order) {
                current = p; engine!.advance(to: p.text)
            }
        }
        saveFinished()
    }
    func backspace(word: Bool) { now = ProcessInfo.processInfo.systemUptime; engine?.backspace(word: word, at: now); saveFinished() }
    func tick() {
        guard phase == .running else { return }
        now = ProcessInfo.processInfo.systemUptime
        var updated = engine!
        updated.tick(at: now)
        if updated.phase != engine?.phase { engine = updated }
        saveFinished()
    }
    func pause() { now = ProcessInfo.processInfo.systemUptime; engine?.pause(at: now); saveFinished() }
    func pauseOrResume() {
        guard !showingFigures else { return }
        now = ProcessInfo.processInfo.systemUptime
        if phase == .paused { engine?.resume(at: now); focus() } else { pause() }
    }
    func navigate(_ destination: String) { if destination != "practice" { pause() }; page = destination; if destination == "practice" { focus() } }
    func saveFinished() { if phase == .finished { archive(reason: engine?.finishReason ?? "Finished") } }
    func archive(reason: String) {
        now = ProcessInfo.processInfo.systemUptime
        engine?.tick(at: now)
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
