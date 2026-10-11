import AppKit
import SwiftUI
import TypingCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            ScopeSidebar(model: model).frame(width: 312)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("The Economy 2.0").font(Typography.font(size: 15, weight: .semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    navButton("Practice", symbol: "keyboard", page: "practice")
                    navButton("History", symbol: "chart.xyaxis.line", page: "history")
                    Button { model.pause(); model.showingSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }.buttonStyle(.plain).help("Settings · ⌘,")
                }.padding(.bottom, 27)
                if let notice = model.notice {
                    HStack { Image(systemName: "exclamationmark.circle"); Text(notice).font(Typography.font(size: 13)); Spacer(); Button("Dismiss") { model.notice = nil }.buttonStyle(.plain) }
                        .padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)).padding(.bottom, 16)
                }
                if model.page == "practice" { PracticeView(model: model) }
                else { HistoryView(model: model) }
                Spacer(minLength: 12)
                HStack {
                    Spacer()
                    Button("Credits and help") { model.pause(); model.showingInfo = true }.buttonStyle(.plain).font(Typography.font(size: 11))
                }.foregroundStyle(Palette.muted).padding(.top, 12)
            }.padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 20)
        }.font(Typography.font(size: 13)).foregroundStyle(Palette.text).background(Palette.background)
        .tint(Palette.accent)
        .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showingInfo) { InfoView(model: model) }
    }
    func navButton(_ title: String, symbol: String, page: String) -> some View {
        Button { model.navigate(page) } label: { Label(title, systemImage: symbol).font(Typography.font(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
                .background(model.page == page ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).foregroundStyle(model.page == page ? Palette.accent : Palette.muted)
    }
}

struct ScopeSidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "book.closed.fill").font(Typography.font(size: 23)).foregroundStyle(Palette.accent)
                Text("COREType").font(Typography.font(size: 23, weight: .semibold))
            }.padding(.bottom, 10)
            HStack { Text("Reading scope").font(Typography.font(size: 13, weight: .semibold)); Spacer(); Text("2 books").font(Typography.font(size: 11)).foregroundStyle(Palette.muted) }
            Picker("Book filter", selection: Binding(get: { model.preferences.bookFilter }, set: { model.bookFilter($0) })) {
                Text("Both").tag("all"); Text("Micro").tag("microeconomics"); Text("Macro").tag("macroeconomics")
            }.pickerStyle(.segmented).labelsHidden().help("Filter the chapter browser. Selection is changed with the checkboxes.")
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search chapters and sections", text: $model.search).textFieldStyle(.plain).font(Typography.font(size: 12))
                if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Button("Select shown") { model.selectVisible(true) }
                Spacer()
                Button("Clear shown") { model.selectVisible(false) }
            }.buttonStyle(.plain).font(Typography.font(size: 11)).foregroundStyle(Palette.accent)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if model.visibleChapters.isEmpty {
                        Text("No matching chapters or sections").font(Typography.font(size: 13)).foregroundStyle(Palette.muted).padding(.vertical, 20)
                    }
                    ForEach(model.visibleChapters) { chapter in
                        chapterRow(chapter)
                        if model.expanded.contains(chapter.id) || !model.search.isEmpty {
                            ForEach(chapter.sections) { section in
                                Button { model.toggleSection(section.id) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: model.selection.contains(section.id) ? "checkmark.square.fill" : "square").foregroundStyle(model.selection.contains(section.id) ? Palette.accent : Palette.muted).padding(.top, 2)
                                        Text(section.title).font(Typography.font(size: 12)).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                        Spacer(minLength: 1)
                                        Text("\(section.passages.count)").font(Typography.font(size: 10)).foregroundStyle(Palette.muted).padding(.top, 2)
                                    }.padding(.vertical, 7).padding(.leading, 24).padding(.trailing, 4).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Select section \(section.title)")
                            }
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            Divider().overlay(.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text("\(model.selectedCount.formatted())").font(Typography.font(size: 23, weight: .medium)).foregroundStyle(Palette.accent); Text("paragraphs selected").font(Typography.font(size: 11)).foregroundStyle(Palette.muted) }
                Button { model.applyScope() } label: {
                    HStack { Text(model.pendingScope ? "Use this selection" : "Selection applied"); Spacer(); Image(systemName: model.pendingScope ? "arrow.right" : "checkmark") }.font(Typography.font(size: 12, weight: .semibold)).padding(12).background(model.pendingScope ? Palette.accent : Palette.panel, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(model.pendingScope ? Palette.background : Palette.muted)
                }.buttonStyle(.plain).disabled(!model.pendingScope)
                Text(model.pendingScope ? "Applying starts a new test" : "Choose chapters or individual sections").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 20).background(Palette.sidebar)
    }
    func chapterRow(_ c: Chapter) -> some View {
        let fullChapter = model.library.chapters.first { $0.id == c.id } ?? c
        let ids = Set(fullChapter.sections.map(\.id))
        let all = ids.isSubset(of: model.selection)
        let some = !ids.isDisjoint(with: model.selection)
        return HStack(alignment: .top, spacing: 8) {
            Button { model.toggleChapter(c) } label: { Image(systemName: all ? "checkmark.square.fill" : some ? "minus.square.fill" : "square").foregroundStyle(some ? Palette.accent : Palette.muted).padding(.top, 2) }.buttonStyle(.plain).accessibilityLabel("Select chapter \(c.unit) \(c.title)")
            Button {
                if model.expanded.contains(c.id) { model.expanded.remove(c.id) } else { model.expanded.insert(c.id) }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(c.book == "microeconomics" ? "Micro" : "Macro") · Unit \(c.unit)").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
                        Text(c.title).font(Typography.font(size: 12, weight: .medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 3)
                    Image(systemName: model.expanded.contains(c.id) ? "chevron.down" : "chevron.right").font(Typography.font(size: 9)).foregroundStyle(Palette.muted).padding(.top, 3)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Expand chapter \(c.unit) \(c.title)")
        }.padding(.vertical, 12).padding(.horizontal, 8).background(Palette.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct PracticeView: View {
    @ObservedObject var model: AppModel
    @ViewState private var customSeconds = "60"
    @ViewState private var customError = false
    @ViewState private var customTimer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Picker("Test mode", selection: Binding(get: { model.preferences.mode }, set: { model.configure(mode: $0) })) { Text("Passage").tag(TestMode.passage); Text("Timed").tag(TestMode.timed) }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                if model.preferences.mode == .timed {
                    Menu {
                        ForEach([15,30,60,120], id: \.self) { s in Button("\(s) seconds") { model.configure(duration: s) } }
                        Divider(); Button("Custom duration…") { model.pause(); customSeconds = String(model.preferences.duration); customError = false; customTimer = true }
                    } label: { Label("\(model.preferences.duration)s", systemImage: "timer").font(Typography.font(size: 13)) }.menuStyle(.borderlessButton).frame(width: 90)
                }
                Spacer()
                Picker("Paragraph order", selection: Binding(get: { model.preferences.order }, set: { model.configure(order: $0) })) { Text("In order").tag(PassagePicker.Order.ordered); Text("Random").tag(PassagePicker.Order.random) }.pickerStyle(.segmented).labelsHidden().frame(width: 180).help("Random chooses a whole paragraph from the applied scope, avoiding immediate repeats when possible.")
            }
            if let passage = model.current, let engine = model.engine {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    MetricTile(title: "WPM", value: String(format: "%.0f", model.metrics.wpm), highlighted: true)
                    MetricTile(title: "Raw WPM", value: String(format: "%.0f", model.metrics.rawWPM))
                    MetricTile(title: "Accuracy", value: String(format: "%.1f%%", model.metrics.accuracy))
                    MetricTile(title: "Mistakes", value: "\(model.metrics.mistakes)")
                    MetricTile(title: model.preferences.mode == .timed ? "Remaining" : "Elapsed", value: String(format: "%.1fs", model.preferences.mode == .timed ? max(0, Double(model.preferences.duration) - model.metrics.elapsed) : model.metrics.elapsed))
                }.padding(.vertical, 5)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(passage.bookTitle) · Unit \(passage.unit)").font(Typography.font(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                            Text(passage.sectionTitle).font(Typography.font(size: 17, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 9) {
                            Text("Paragraph \(passage.paragraph)").font(Typography.font(size: 13)).foregroundStyle(Palette.muted)
                        }
                    }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 15)
                    Rectangle().fill(.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 28)
                    TypingSurface(model: model).frame(minHeight: 195, maxHeight: .infinity)
                    HStack {
                        Circle().fill(model.phase == .finished ? Palette.green : model.focused ? Palette.accent : Palette.muted).frame(width: 6, height: 6)
                        Text(statusText).font(Typography.font(size: 11))
                        Spacer()
                        Text("\(engine.input.count) / \(engine.target.count) characters").font(Typography.font(size: 10))
                    }.foregroundStyle(Palette.muted).padding(.horizontal, 28).padding(.vertical, 14)
                }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                if model.phase == .finished {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(engine.finishReason ?? "Complete", systemImage: "checkmark.circle.fill").font(Typography.font(size: 17, weight: .medium)).foregroundStyle(Palette.green)
                            Text("\(model.metrics.correctCharacters) correct characters · \(model.metrics.corrected) corrections · \(model.metrics.uncorrected) remaining errors").font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                            Text(String(format: "Error rate %.1f%% · %d paragraphs completed", model.metrics.errorRate, engine.completedParagraphs)).font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("View history") { model.navigate("history") }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    }
                }
                HStack(spacing: 18) {
                    Button { model.restart() } label: { Label("Repeat", systemImage: "arrow.counterclockwise").font(Typography.font(size: 12)) }.buttonStyle(.plain).help("Repeat the starting paragraph · ⌘R")
                    Text("⌘R").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
                    if model.phase == .running || model.phase == .paused { Button(model.phase == .paused ? "Resume" : "Pause") { model.pauseOrResume() }.buttonStyle(.plain).font(Typography.font(size: 12)).help("Escape or ⌘P") }
                    Spacer()
                    Text("⌘N").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
                    Button { model.next() } label: { Label("Next paragraph", systemImage: "arrow.right").font(Typography.font(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11).background(Palette.accent, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Palette.background) }.buttonStyle(.plain)
                }.foregroundStyle(Palette.text)
            } else {
                VStack(spacing: 17) {
                    Image(systemName: "books.vertical").font(Typography.font(size: 39)).foregroundStyle(Palette.accent)
                    Text("Select a reading scope").font(Typography.font(size: 22, weight: .semibold))
                    Text("Select chapters or sections, then click Use this selection.").font(Typography.font(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button("Select all textbooks") { model.selection = model.library.sectionIDs; model.applyScope() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(35).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            }
        }.sheet(isPresented: $customTimer) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Custom duration").font(Typography.font(size: 20, weight: .semibold))
                Text("Enter 1–3,600 seconds.").foregroundStyle(Palette.muted)
                TextField("Seconds", text: $customSeconds).textFieldStyle(.roundedBorder).onSubmit { applyCustom() }
                if customError { Text("Use a whole number from 1 to 3,600.").foregroundStyle(.red).font(Typography.font(size: 13)) }
                HStack { Button("Cancel") { customTimer = false }.keyboardShortcut(.cancelAction); Spacer(); Button("Use duration") { applyCustom() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
            }.padding(30).frame(width: 350).background(Palette.background)
        }
    }
    var statusText: String {
        switch model.phase {
        case .ready: return model.focused ? "Ready to type" : "Click to type · ⌘T"
        case .running: return model.focused ? "Typing · Esc to pause" : "Click to type · ⌘T"
        case .paused: return "Paused"
        case .finished: return "Saved · Return for next paragraph"
        }
    }
    func applyCustom() {
        guard let value = Int(customSeconds), (1...3600).contains(value) else { customError = true; return }
        model.configure(duration: value); customTimer = false
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var highlighted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(value).font(Typography.font(size: 32)).monospacedDigit().foregroundStyle(highlighted ? Palette.accent : Palette.text)
            Text(title).font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ViewState private var showInterrupted = false
    var completed: [TestResult] { model.results.filter(\.completed) }
    var shown: [TestResult] { showInterrupted ? model.results : completed }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                MetricTile(title: "Completed tests", value: "\(completed.count)", highlighted: true)
                MetricTile(title: "Average WPM", value: completed.isEmpty ? "—" : String(format: "%.0f", completed.map { $0.metrics.wpm }.reduce(0,+) / Double(completed.count)))
                MetricTile(title: "Best WPM", value: completed.isEmpty ? "—" : String(format: "%.0f", completed.map { $0.metrics.wpm }.max() ?? 0))
            }
            if !completed.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("WPM · Last \(min(25, completed.count)) completed tests").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
                    Canvas { context, size in
                        let values = Array(completed.prefix(25).reversed()).map { $0.metrics.wpm }
                        let maximum = max(20, (values.max() ?? 0) * 1.1)
                        var line = Path()
                        for (i,value) in values.enumerated() {
                            let point = CGPoint(x: values.count == 1 ? size.width / 2 : size.width * Double(i) / Double(values.count-1), y: size.height - size.height * value / maximum)
                            if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
                            context.fill(Path(ellipseIn: CGRect(x: point.x-3,y: point.y-3,width: 6,height: 6)), with: .color(Palette.accent))
                        }
                        context.stroke(line, with: .color(Palette.accent), lineWidth: 2)
                    }.frame(height: 78)
                }.padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack { Toggle("Show interrupted tests", isOn: $showInterrupted).toggleStyle(.checkbox).font(Typography.font(size: 12)); Spacer(); Button("Export CSV") { model.exportHistory() }.disabled(model.results.isEmpty).buttonStyle(.bordered) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if shown.isEmpty { Text(showInterrupted ? "No tests yet" : "No completed tests").foregroundStyle(Palette.muted).padding(.vertical, 35) }
                    ForEach(shown) { result in
                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.label).font(Typography.font(size: 13, weight: .medium)).lineLimit(2)
                                Text("\(result.book) · \(result.date.formatted(date: .abbreviated, time: .shortened))").font(Typography.font(size: 10)).foregroundStyle(Palette.muted)
                                Text("\(result.reason) · \(result.mode == .timed ? "\(result.duration)s timed" : "passage") · \(String(format: "%.1fs", result.metrics.elapsed))").font(Typography.font(size: 10)).foregroundStyle(result.completed ? Palette.green : Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 5) { Text(String(format: "%.0f", result.metrics.wpm)).font(Typography.font(size: 24)).foregroundStyle(Palette.accent); Text("WPM").font(Typography.font(size: 9)).foregroundStyle(Palette.muted) }
                            VStack(alignment: .trailing, spacing: 5) { Text(String(format: "%.1f%%", result.metrics.accuracy)).font(Typography.font(size: 14)); Text("accuracy").font(Typography.font(size: 9)).foregroundStyle(Palette.muted) }
                            Button { model.replay(result) } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).help("Practice this starting paragraph again")
                        }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Text("Stores the latest 1,000 tests. Averages include completed tests.").font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Text("Settings").font(Typography.font(size: 22, weight: .semibold)); Spacer(); Button("Done") { dismiss(); model.focus() }.keyboardShortcut(.defaultAction) }
            Toggle("Show textbook figures and tables", isOn: Binding(get: { model.preferences.showTextbookMedia }, set: { model.showTextbookMedia($0) }))
            Text("Show referenced material with the passage as you type.").font(Typography.font(size: 13)).foregroundStyle(Palette.muted)
            Toggle("Accept equivalent keyboard punctuation", isOn: Binding(get: { model.preferences.flexiblePunctuation }, set: { model.configure(punctuation: $0) }))
            Text("Matches straight and curly quotes, and hyphens with en or em dashes. Other characters must match exactly. Source text is unchanged.").font(Typography.font(size: 13)).foregroundStyle(Palette.muted)
            HStack { Text("Passage text size"); Spacer(); Text("\(Int(model.preferences.fontSize)) pt").monospacedDigit() }
            Slider(value: Binding(get: { model.preferences.fontSize }, set: { model.fontSize($0) }), in: 18...32, step: 1)
            Divider()
            Text("Keyboard shortcuts").font(Typography.font(size: 14, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                GridRow { Text("Repeat test"); Text("⌘R") }
                GridRow { Text("Next paragraph"); Text("⌘N") }
                GridRow { Text("Pause or resume"); Text("Esc / ⌘P") }
                GridRow { Text("Focus passage"); Text("⌘T") }
                GridRow { Text("Practice / History"); Text("⌘1 / ⌘2") }
                GridRow { Text("Delete character"); Text("Backspace") }
                GridRow { Text("Delete previous word"); Text("⌥Backspace") }
            }.font(Typography.font(size: 12))
            Text("The timer pauses when the app loses focus. Pasting is disabled. Settings are saved on this Mac.").font(Typography.font(size: 13)).foregroundStyle(Palette.muted)
        }.padding(32).frame(width: 560).font(Typography.font(size: 13)).foregroundStyle(Palette.text).background(Palette.background)
    }
}

struct InfoView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack { Text("COREType").font(Typography.font(size: 29, weight: .medium)).foregroundStyle(Palette.accent); Spacer(); Button("Done") { dismiss(); model.focus() }.keyboardShortcut(.defaultAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    Text("Offline typing practice using Sasha's prepared CORE Econ excerpts.").font(Typography.font(size: 13))
                    Text("6,893 paragraphs · 20 chapters · 271 sections").font(Typography.font(size: 14, weight: .semibold))
                    Text("The sidebar filters the chapter browser. Check chapters or sections and click Use this selection to change your practice scope. Random chooses within the applied scope, avoiding immediate repeats when more than one paragraph is available. In order follows book, unit, section, and paragraph order, then wraps. Timed tests continue with another complete excerpt as soon as the current one is typed.").font(Typography.font(size: 13))
                    Text("Textbook figures and tables").font(Typography.font(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                    Text("Referenced figures and tables appear with the passage in the typing area. Scroll to read them while practising. Show or hide them in Settings; the choice is saved on this Mac. Captions and credits come from the original textbook.").font(Typography.font(size: 13))
                    Text("Metrics").font(Typography.font(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                    Text("WPM = retained correct characters ÷ 5 ÷ active minutes.\nRaw WPM = all character attempts ÷ 5 ÷ active minutes, including corrected or repeated characters.\nAccuracy = correct character attempts ÷ all character attempts.\nError rate = incorrect character attempts ÷ all character attempts.\nMistakes count incorrect attempts, even when corrected. Corrections count incorrect characters removed with Backspace. Remaining errors count wrong characters still in the typed text.\nSpaces and punctuation count as characters. Backspace is not a character attempt. Paused time is excluded. Very short tests can produce unstable speed estimates.").font(Typography.font(size: 13)).lineSpacing(5)
                    Text("About the excerpts").font(Typography.font(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                    Text("The prepared collection excludes front matter, glossaries, references, and equation-heavy material. Some LaTeX notation, exercises, and extension prose remain. Some long source paragraphs were split during preparation. Imported text, order, and verified section metadata are preserved.").font(Typography.font(size: 13))
                    Text(model.attribution).font(Typography.font(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    Text("Local data: \(model.stateFile.url.path)").font(Typography.font(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
            }
        }.padding(32).frame(width: 640, height: 660).font(Typography.font(size: 13)).foregroundStyle(Palette.text).background(Palette.background)
    }
}
