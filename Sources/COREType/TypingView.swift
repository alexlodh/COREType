import AppKit
import SwiftUI
import TypingCore

final class PassageTextView: NSTextView {
    var onInput: (String) -> Void = { _ in }
    var onBackspace: (Bool) -> Void = { _ in }
    var onPause: () -> Void = {}
    var onNext: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
    var caretOffset = 0
    var phase: Phase = .ready { didSet { if phase != oldValue { reconcileBlink(); invalidateCaret() } } }
    var lastFocus = -1
    var lastKeystroke = ProcessInfo.processInfo.systemUptime
    private var blinkTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var caretRect = NSRect.zero

    deinit {
        blinkTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        blinkTimer?.invalidate(); blinkTimer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        guard let window else { return }
        let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification,
            NSView.boundsDidChangeNotification]
        enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
        for name in names {
            let source: Any? = name == NSView.boundsDidChangeNotification ? enclosingScrollView?.contentView :
                (name == NSApplication.didBecomeActiveNotification || name == NSApplication.didResignActiveNotification ? nil : window)
            observers.append(NotificationCenter.default.addObserver(forName: name, object: source, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcileBlink(); self?.invalidateCaret() }
            })
        }
        reconcileBlink()
    }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        onFocus(true)
        DispatchQueue.main.async { [weak self] in self?.reconcileBlink(); self?.invalidateCaret() }
        return true
    }
    override func resignFirstResponder() -> Bool {
        onFocus(false); blinkTimer?.invalidate(); blinkTimer = nil; invalidateCaret(); return true
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); invalidateCaret() }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "v" { NSSound.beep(); return }
            super.keyDown(with: event); return
        }
        lastKeystroke = ProcessInfo.processInfo.systemUptime
        invalidateCaret()
        switch event.keyCode {
        case 51, 117: onBackspace(event.modifierFlags.contains(.option))
        case 53: onPause()
        case 36, 76: if phase == .finished { onNext() }
        case 48: window?.selectNextKeyView(self)
        case 123...126: break
        default: interpretKeyEvents([event])
        }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let string = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        lastKeystroke = ProcessInfo.processInfo.systemUptime
        onInput(string)
        invalidateCaret()
    }
    override func paste(_ sender: Any?) { NSSound.beep() }

    func refreshCaretGeometry() {
        let old = caretRect
        caretRect = .zero
        if let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 {
            // Layout is already current after genuine geometry edits. Never force
            // full text layout from draw() or the cosmetic blink timer.
            let index = min(caretOffset, storage.length - 1)
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            rect.origin.x += textContainerOrigin.x + (caretOffset >= storage.length ? rect.width : 0)
            rect.origin.y = line.origin.y + textContainerOrigin.y + 3
            rect.size.width = 2.5; rect.size.height = max(20, line.height - 7)
            caretRect = rect
        }
        if !old.isEmpty { setNeedsDisplay(old.insetBy(dx: -2, dy: -2)) }
        invalidateCaret(); reconcileBlink()
    }
    private var caretRelevant: Bool {
        guard let window else { return false }
        return (phase == .ready || phase == .running) && NSApp.isActive && window.isKeyWindow && window.isVisible &&
            window.occlusionState.contains(.visible) &&
            !window.isMiniaturized && window.firstResponder === self && !isHiddenOrHasHiddenAncestor &&
            !caretRect.isEmpty && visibleRect.intersects(caretRect)
    }
    func reconcileBlink() {
        guard caretRelevant else { blinkTimer?.invalidate(); blinkTimer = nil; return }
        guard blinkTimer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reconcileBlink()
                if self.caretRelevant { PerformanceCounters.record("caret.blinks"); self.invalidateCaret() }
            }
        }
        timer.tolerance = 0.04
        blinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func invalidateCaret() {
        guard !caretRect.isEmpty else { return }
        PerformanceCounters.record("caret.regionInvalidations")
        setNeedsDisplay(caretRect.insetBy(dx: -2, dy: -2))
    }
    override func draw(_ dirtyRect: NSRect) {
        PerformanceCounters.record("text.draws")
        super.draw(dirtyRect)
        guard caretRelevant, dirtyRect.intersects(caretRect) else { return }
        let age = ProcessInfo.processInfo.systemUptime - lastKeystroke
        let alpha = age < 0.5 || Int(age * 2) % 2 == 0 ? 1.0 : 0.25
        NSColor(red: 0.95, green: 0.73, blue: 0.42, alpha: alpha).setFill()
        NSBezierPath(roundedRect: caretRect, xRadius: 1, yRadius: 1).fill()
    }
}

/// One document keeps the passage and its source material in the same scroll.
final class PassageDocumentView: NSView {
    let textView = PassageTextView(frame: .zero)
    let mediaView = InlineTextbookDocumentView(frame: .zero)
    var hasMedia = false
    private var lastViewport = NSSize.zero
    private var lastMediaHeight: CGFloat = -1
    private var lastHasMedia = false
    private var textHeight: CGFloat = 0
    private var layoutDirty = true
    private var lastPassageRevision: UInt64?
    private var lastInputRevision: UInt64?
    private var lastEngineInputRevision: UInt64 = 0
    private var lastFontSize: Double?
    private var lastInput: [Character] = []
    private var map: PassageUTF16Map?
    private var lastMediaRevision: UInt64?
    private var lastMediaEnabled: Bool?
    private var baseAttributes: [NSAttributedString.Key: Any] = [:]
    private var correctAttributes: [NSAttributedString.Key: Any] = [:]
    private var errorAttributes: [NSAttributedString.Key: Any] = [:]
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView); addSubview(mediaView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Returns true only when displayed input or the base passage/style changed.
    @discardableResult func render(engine: TypingEngine, passageRevision: UInt64, inputRevision: UInt64, fontSize: Double) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let rebuild = lastPassageRevision != passageRevision || lastFontSize != fontSize || map == nil
        guard rebuild || lastInputRevision != inputRevision else { return false }
        storage.beginEditing()
        if rebuild {
            PerformanceCounters.record("text.fullRebuilds")
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8; paragraph.lineBreakMode = .byWordWrapping
            baseAttributes = [.font: Typography.passageFont(size: fontSize), .foregroundColor: Palette.untypedColor, .paragraphStyle: paragraph]
            correctAttributes = baseAttributes; correctAttributes[.foregroundColor] = Palette.textColor
            errorAttributes = baseAttributes; errorAttributes[.foregroundColor] = Palette.errorColor
            errorAttributes[.backgroundColor] = NSColor(red: 0.8, green: 0.2, blue: 0.28, alpha: 0.17)
            errorAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            storage.setAttributedString(NSAttributedString(string: String(engine.target), attributes: baseAttributes))
            map = PassageUTF16Map(target: engine.target)
            lastInput = []
            layoutDirty = true
        }
        var start = 0
        if !rebuild {
            let added = engine.input.count - lastInput.count
            if added > 0 && engine.inputRevision &- lastEngineInputRevision == UInt64(added) {
                // Each accepted append increments the revision; any intervening
                // deletion makes this equality impossible. The common path is O(1).
                start = lastInput.count
            } else {
                // Character equality normalizes Unicode. Wrong glyphs must keep
                // their actual encoding (é and e + combining accent differ in UTF-16).
                while start < min(lastInput.count, engine.input.count) &&
                    String(lastInput[start]).utf16.elementsEqual(String(engine.input[start]).utf16) { start += 1 }
            }
        }
        let end = max(lastInput.count, engine.input.count)
        if end > start {
            PerformanceCounters.record("text.incrementalEdits", amount: end - start)
            for index in (start..<end).reversed() {
                let expected = engine.target[index]
                let oldTyped = index < lastInput.count ? lastInput[index] : nil
                let typed = index < engine.input.count ? engine.input[index] : nil
                let oldCorrect = oldTyped.map { engine.matches($0, expected) } ?? false
                let correct = typed.map { engine.matches($0, expected) } ?? false
                let oldCharacter = oldTyped != nil && !oldCorrect && oldTyped != " " ? oldTyped! : expected
                let character = typed != nil && !correct && typed != " " ? typed! : expected
                let range = map!.range(at: index)
                if !String(oldCharacter).utf16.elementsEqual(String(character).utf16) {
                    storage.replaceCharacters(in: range, with: String(character))
                    layoutDirty = true
                }
                let newRange = NSRange(location: range.location, length: String(character).utf16.count)
                storage.setAttributes(typed == nil ? baseAttributes : correct ? correctAttributes : errorAttributes, range: newRange)
            }
            let displayed = engine.input[start...].enumerated().map { offset, typed -> Character in
                let expected = engine.target[start + offset]
                return !engine.matches(typed, expected) && typed != " " ? typed : expected
            }
            map!.replaceTypedSuffix(from: start, displayed: displayed)
        }
        storage.endEditing()
        textView.caretOffset = map!.offset(at: engine.input.count)
        textView.setAccessibilityValue("\(engine.input.count) of \(engine.target.count) characters typed. \(engine.mistakes) mistakes.")
        lastInput = engine.input
        lastEngineInputRevision = engine.inputRevision
        lastPassageRevision = passageRevision; lastInputRevision = inputRevision; lastFontSize = fontSize
        return true
    }

    func updateMedia(figures: [TextbookFigure], revision: UInt64, enabled: Bool, catalogue: FigureCatalogue, root: URL) {
        guard lastMediaRevision != revision || lastMediaEnabled != enabled else { return }
        lastMediaRevision = revision; lastMediaEnabled = enabled
        let visible = enabled ? figures : []
        hasMedia = !visible.isEmpty
        mediaView.update(figures: visible, catalogue: catalogue, resourceRoot: root)
    }

    func fit(to viewport: NSSize) {
        guard viewport.width > 0 else { return }
        let widthChanged = viewport.width != lastViewport.width
        let mediaHeight = hasMedia ? mediaView.contentHeight : 0
        guard layoutDirty || viewport != lastViewport || hasMedia != lastHasMedia || mediaHeight != lastMediaHeight else { return }
        PerformanceCounters.record("document.fits")
        if textView.frame.width != viewport.width { textView.setFrameSize(NSSize(width: viewport.width, height: textView.frame.height)) }
        if let layout = textView.layoutManager, let container = textView.textContainer {
            if layoutDirty || widthChanged {
                let size = NSSize(width: max(1, viewport.width - textView.textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
                if container.containerSize != size { container.containerSize = size }
                PerformanceCounters.record("text.fullLayouts")
                layout.ensureLayout(for: container)
                textHeight = ceil(layout.usedRect(for: container).maxY) + textView.textContainerInset.height * 2
            }
            let passageHeight = hasMedia ? textHeight : max(textHeight, viewport.height)
            let textSize = NSSize(width: viewport.width, height: passageHeight)
            if textView.frame.size != textSize { textView.setFrameSize(textSize) }
            mediaView.isHidden = !hasMedia
            let mediaFrame = NSRect(x: 28, y: passageHeight + (hasMedia ? 12 : 0), width: max(1, viewport.width - 56), height: mediaHeight)
            if mediaView.frame != mediaFrame { mediaView.frame = mediaFrame }
            let size = NSSize(width: viewport.width, height: max(viewport.height, mediaFrame.maxY))
            if frame.size != size { setFrameSize(size) }
        }
        layoutDirty = false; lastViewport = viewport; lastHasMedia = hasMedia; lastMediaHeight = mediaHeight
        textView.refreshCaretGeometry()
    }
}

final class PassageScrollView: NSScrollView {
    private var lastViewport = NSSize.zero
    override func layout() {
        super.layout()
        guard contentSize != lastViewport, let document = documentView as? PassageDocumentView else { return }
        lastViewport = contentSize
        document.fit(to: contentSize)
        if document.textView.caretOffset > 0 {
            DispatchQueue.main.async { [weak document] in
                guard let view = document?.textView, let length = view.textStorage?.length, length > 0 else { return }
                view.scrollRangeToVisible(NSRange(location: min(view.caretOffset, length - 1), length: 1))
                view.reconcileBlink()
            }
        }
    }
}

struct TypingSurface: NSViewRepresentable {
    let model: AppModel
    let engine: TypingEngine
    let passageRevision: UInt64
    let inputRevision: UInt64
    let fontSize: Double
    let figures: [TextbookFigure]
    let mediaRevision: UInt64
    let showTextbookMedia: Bool
    let focusToken: Int
    let page: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PassageScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let document = PassageDocumentView(frame: .zero)
        let view = document.textView
        view.isEditable = false; view.isSelectable = false; view.isRichText = false
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 28, height: 26)
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true; view.textContainer?.heightTracksTextView = false
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = NSSize(width: 0, height: 0)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.setAccessibilityLabel("Typing passage")
        view.setAccessibilityHelp("Type the displayed paragraph. Command R repeats; Command N selects the next paragraph; Escape pauses.")
        view.onInput = { model.type($0) }; view.onBackspace = { model.backspace(word: $0) }
        view.onPause = { model.pauseOrResume() }; view.onNext = { model.next() }
        view.onFocus = { value in DispatchQueue.main.async { model.focused = value } }
        document.mediaView.onHeightChanged = { [weak document, weak scroll] in
            guard let document, let scroll else { return }
            document.fit(to: scroll.contentSize)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        document.mediaView.onFocusTyping = { [weak view] in
            guard let view else { return }; view.window?.makeFirstResponder(view)
        }
        scroll.documentView = document
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        PerformanceCounters.record("surface.updates")
        guard let document = scroll.documentView as? PassageDocumentView else { return }
        let view = document.textView
        view.phase = engine.phase
        document.updateMedia(figures: figures, revision: mediaRevision, enabled: showTextbookMedia, catalogue: model.figureCatalogue, root: model.resourceRoot)
        let changed = document.render(engine: engine, passageRevision: passageRevision, inputRevision: inputRevision, fontSize: fontSize)
        document.fit(to: scroll.contentSize)
        if changed {
            view.refreshCaretGeometry()
            if engine.input.isEmpty { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
            else { view.scrollRangeToVisible(NSRange(location: min(view.caretOffset, max(0, (view.textStorage?.length ?? 0) - 1)), length: 1)) }
            view.reconcileBlink()
        }
        if view.lastFocus != focusToken {
            view.lastFocus = focusToken
            DispatchQueue.main.async { if page == "practice" { view.window?.makeFirstResponder(view) } }
        }
    }
}
