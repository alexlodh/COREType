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
    var phase: Phase = .ready
    var lastSignature = ""
    var lastFocus = -1
    var lastKeystroke = ProcessInfo.processInfo.systemUptime
    private var blinkTimer: Timer?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        blinkTimer?.invalidate()
        if window != nil {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        }
    }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { onFocus(true); needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { onFocus(false); needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "v" { NSSound.beep(); return }
            super.keyDown(with: event); return
        }
        lastKeystroke = ProcessInfo.processInfo.systemUptime
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
        onInput(string)
    }
    override func paste(_ sender: Any?) { NSSound.beep() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self, phase == .ready || phase == .running,
              let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let index = min(caretOffset, storage.length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.origin.x += textContainerOrigin.x + (caretOffset >= storage.length ? rect.width : 0)
        rect.origin.y = line.origin.y + textContainerOrigin.y + 3
        rect.size.width = 2.5; rect.size.height = max(20, line.height - 7)
        let age = ProcessInfo.processInfo.systemUptime - lastKeystroke
        let alpha = age < 0.5 || Int(age * 2) % 2 == 0 ? 1.0 : 0.25
        NSColor(red: 0.95, green: 0.73, blue: 0.42, alpha: alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
}

/// One document keeps the passage and its source material in the same scroll.
final class PassageDocumentView: NSView {
    let textView = PassageTextView(frame: .zero)
    let mediaView = InlineTextbookDocumentView(frame: .zero)
    var hasMedia = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(mediaView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func fit(to viewport: NSSize) {
        guard viewport.width > 0 else { return }
        textView.setFrameSize(NSSize(width: viewport.width, height: textView.frame.height))
        if let layout = textView.layoutManager, let container = textView.textContainer {
            container.containerSize = NSSize(width: max(1, viewport.width - textView.textContainerInset.width * 2),
                                             height: CGFloat.greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            let textHeight = ceil(layout.usedRect(for: container).maxY) + textView.textContainerInset.height * 2
            let mediaHeight = hasMedia ? mediaView.contentHeight : 0
            let passageHeight = hasMedia ? textHeight : max(textHeight, viewport.height)
            textView.setFrameSize(NSSize(width: viewport.width, height: passageHeight))
            mediaView.isHidden = !hasMedia
            mediaView.frame = NSRect(x: 28, y: passageHeight + (hasMedia ? 12 : 0),
                                     width: max(1, viewport.width - 56), height: mediaHeight)
            setFrameSize(NSSize(width: viewport.width, height: max(viewport.height, mediaView.frame.maxY)))
        }
    }
}

final class PassageScrollView: NSScrollView {
    private var lastViewport = NSSize.zero
    override func layout() {
        super.layout()
        guard contentSize != lastViewport, let document = documentView as? PassageDocumentView else { return }
        lastViewport = contentSize
        document.fit(to: contentSize)
        // Resizing should keep the active caret visible. Media loads and timer
        // ticks do not move the user's scroll position while reading a figure.
        if document.textView.caretOffset > 0 {
            DispatchQueue.main.async { [weak document] in
                guard let view = document?.textView, let length = view.textStorage?.length, length > 0 else { return }
                view.scrollRangeToVisible(NSRange(location: min(view.caretOffset, length - 1), length: 1))
            }
        }
    }
}

struct TypingSurface: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PassageScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let document = PassageDocumentView(frame: .zero)
        let view = document.textView
        view.isEditable = false; view.isSelectable = false; view.isRichText = false
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 28, height: 26)
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
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
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
        scroll.documentView = document
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let document = scroll.documentView as? PassageDocumentView, let engine = model.engine else { return }
        let view = document.textView
        view.phase = engine.phase
        let figures = model.preferences.showTextbookMedia ? model.currentFigures : []
        document.hasMedia = !figures.isEmpty
        document.mediaView.update(figures: figures, catalogue: model.figureCatalogue, resourceRoot: model.resourceRoot)
        let signature = String(engine.target) + "\u{0000}" + String(engine.input) + "\(model.preferences.fontSize)"
        if signature != view.lastSignature {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8; paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [.font: Typography.passageFont(size: model.preferences.fontSize),
                .foregroundColor: Palette.untypedColor, .paragraphStyle: paragraph]
            let display = NSMutableAttributedString(string: "")
            var offset = 0
            for (i, expected) in engine.target.enumerated() {
                let typed = i < engine.input.count ? engine.input[i] : nil
                let correct = typed.map { engine.matches($0, expected) } ?? false
                let character = typed != nil && !correct && typed != " " ? typed! : expected
                let piece = NSMutableAttributedString(string: String(character), attributes: attributes)
                if typed != nil {
                    piece.addAttribute(.foregroundColor, value: correct ? Palette.textColor : Palette.errorColor, range: NSRange(location: 0, length: piece.length))
                    if !correct {
                        piece.addAttribute(.backgroundColor, value: NSColor(red: 0.8, green: 0.2, blue: 0.28, alpha: 0.17), range: NSRange(location: 0, length: piece.length))
                        piece.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: piece.length))
                    }
                }
                display.append(piece)
                if i < engine.input.count { offset += piece.length }
            }
            view.textStorage?.setAttributedString(display); view.caretOffset = offset
            view.setAccessibilityValue("\(engine.input.count) of \(engine.target.count) characters typed. \(engine.mistakes) mistakes.")
            view.lastSignature = signature
            document.fit(to: scroll.contentSize)
            if engine.input.isEmpty { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
            else { view.scrollRangeToVisible(NSRange(location: min(offset, max(0, display.length - 1)), length: 1)) }
        } else { document.fit(to: scroll.contentSize) }
        if view.lastFocus != model.focusToken {
            view.lastFocus = model.focusToken
            DispatchQueue.main.async { if model.page == "practice" { view.window?.makeFirstResponder(view) } }
        }
        view.needsDisplay = true
    }
}
