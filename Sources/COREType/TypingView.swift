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

final class PassageScrollView: NSScrollView {
    private var lastViewport = NSSize.zero
    override func layout() {
        super.layout()
        guard contentSize != lastViewport else { return }
        lastViewport = contentSize
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.documentView as? PassageTextView, view.caretOffset > 0,
                  let length = view.textStorage?.length, length > 0 else { return }
            view.scrollRangeToVisible(NSRange(location: min(view.caretOffset, length - 1), length: 1))
        }
    }
}

struct TypingSurface: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PassageScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let view = PassageTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = false; view.isRichText = false
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 28, height: 26)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
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
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PassageTextView, let engine = model.engine else { return }
        view.phase = engine.phase
        let signature = String(engine.target) + "\u{0000}" + String(engine.input) + "\(model.preferences.fontSize)"
        if signature != view.lastSignature {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8; paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [.font: Typography.passageFont(size: model.preferences.fontSize),
                .foregroundColor: NSColor(red: 0.45, green: 0.49, blue: 0.53, alpha: 1), .paragraphStyle: paragraph]
            let display = NSMutableAttributedString(string: "")
            var offset = 0
            for (i, expected) in engine.target.enumerated() {
                let typed = i < engine.input.count ? engine.input[i] : nil
                let correct = typed.map { engine.matches($0, expected) } ?? false
                let character = typed != nil && !correct && typed != " " ? typed! : expected
                let piece = NSMutableAttributedString(string: String(character), attributes: attributes)
                if let typed {
                    piece.addAttribute(.foregroundColor, value: correct ? NSColor(red: 0.88, green: 0.9, blue: 0.87, alpha: 1) : NSColor(red: 1, green: 0.42, blue: 0.45, alpha: 1), range: NSRange(location: 0, length: piece.length))
                    if !correct {
                        piece.addAttribute(.backgroundColor, value: NSColor(red: 0.8, green: 0.2, blue: 0.28, alpha: 0.17), range: NSRange(location: 0, length: piece.length))
                        piece.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: piece.length))
                    }
                    _ = typed
                }
                display.append(piece)
                if i < engine.input.count { offset += piece.length }
            }
            view.textStorage?.setAttributedString(display); view.caretOffset = offset
            view.setAccessibilityValue("\(engine.input.count) of \(engine.target.count) characters typed. \(engine.mistakes) mistakes.")
            view.lastSignature = signature
            if engine.input.isEmpty { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
            else { view.scrollRangeToVisible(NSRange(location: min(offset, max(0, display.length - 1)), length: 1)) }
        }
        if view.lastFocus != model.focusToken {
            view.lastFocus = model.focusToken
            DispatchQueue.main.async { if model.page == "practice" { view.window?.makeFirstResponder(view) } }
        }
        view.needsDisplay = true
    }
}
