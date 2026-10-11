import AppKit
import WebKit
import TypingCore

/// The referenced source material is part of the typing document's shared scroll.
/// The web view has its full content height; only wide tables scroll within it.
final class InlineTextbookDocumentView: NSView {
    var onHeightChanged: () -> Void = {}
    var onFocusTyping: () -> Void = {}
    private(set) var contentHeight: CGFloat = 0
    private let renderer = InlineTextbookRenderer()
    // Keep the wrapper cheap for passages without references. Once created,
    // retain one renderer so toggling media does not repeatedly start WebKit.
    private var webView: InlineTextbookWebView?
    private var figures: [TextbookFigure] = []
    private var resourceRoot: URL?
    private var renderedFigures: [TextbookFigure] = []
    private var renderedRoot: URL?
    private var renderedHeight: CGFloat = 0
    private var measuredWidth: CGFloat = -1
    private var documentVersion = 0
    private var measurementRequested = false
    private var measurementScheduled = false
    private var measurementInFlight = false
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        renderer.onLoad = { [weak self] in self?.requestHeightMeasurement() }
    }

    private func makeWebView() -> InlineTextbookWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(renderer, forURLScheme: InlineTextbookRenderer.scheme)
        let webView = InlineTextbookWebView(frame: bounds, configuration: configuration)
        webView.navigationDelegate = renderer
        webView.underPageBackgroundColor = NSColor(Palette.panel)
        webView.setAccessibilityLabel("Referenced textbook figures and tables")
        addSubview(webView)
        self.webView = webView
        PerformanceCounters.record("web.creations")
        return webView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
    }

    private func updateEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        guard window != nil, !figures.isEmpty else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, event.window === self.window,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            if event.type == .scrollWheel {
                if !event.modifierFlags.contains(.shift),
                   abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                   let scroll = self.enclosingScrollView {
                    scroll.scrollWheel(with: event)
                    return nil
                }
                return event
            }
            // WebKit content subviews can become first responder even though the
            // web view itself declines focus. Keep typing directed to the passage.
            DispatchQueue.main.async { [weak self] in self?.onFocusTyping() }
            return event
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func layout() {
        super.layout()
        guard let webView else { return }
        if webView.frame != bounds { webView.frame = bounds }
        if abs(bounds.width - measuredWidth) > 0.5 {
            measuredWidth = bounds.width
            requestHeightMeasurement()
        }
    }

    func update(figures: [TextbookFigure], catalogue: FigureCatalogue, resourceRoot: URL) {
        guard self.figures != figures || self.resourceRoot != resourceRoot else { return }
        self.figures = figures
        self.resourceRoot = resourceRoot
        updateEventMonitor()
        documentVersion += 1
        measurementRequested = false
        guard !figures.isEmpty else {
            // Never load an empty document. Cancel an unfinished navigation;
            // a completed document can be reused when its media is shown again.
            if !renderer.loaded {
                webView?.stopLoading()
                renderer.navigation = nil
                renderedFigures = []
                renderedRoot = nil
            }
            setContentHeight(0)
            return
        }
        if renderer.loaded, renderedFigures == figures, renderedRoot == resourceRoot {
            setContentHeight(renderedHeight)
            requestHeightMeasurement()
            return
        }
        let webView = makeWebView()
        webView.stopLoading()
        renderer.loaded = false
        renderer.navigation = nil
        renderer.assets.removeAll()
        renderedFigures = figures
        renderedRoot = resourceRoot
        renderedHeight = 0
        measuredWidth = -1
        setContentHeight(0)
        PerformanceCounters.record("media.htmlLoads")
        renderer.navigation = webView.loadHTMLString(renderer.document(figures: figures, catalogue: catalogue,
                                                                       root: resourceRoot, version: documentVersion), baseURL: nil)
    }

    private func requestHeightMeasurement() {
        guard renderer.loaded, bounds.width > 0, !figures.isEmpty else { return }
        measurementRequested = true
        guard !measurementScheduled, !measurementInFlight else { return }
        measurementScheduled = true
        // Width changes and navigation completion often arrive in the same
        // layout turn. Query once after the final frame has been assigned.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementScheduled = false
            self.measureHeight()
        }
    }

    private func measureHeight() {
        guard measurementRequested, !measurementInFlight, renderer.loaded,
              bounds.width > 0, !figures.isEmpty, let webView else { return }
        measurementRequested = false
        measurementInFlight = true
        let version = documentVersion
        let width = bounds.width
        // This fixed app query only measures layout. Source content cannot run
        // JavaScript, and the isolated client world has no source scripts.
        PerformanceCounters.record("media.heightQueries")
        webView.evaluateJavaScript("Math.ceil(document.getElementById('textbook').getBoundingClientRect().height)",
                                   in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            self.measurementInFlight = false
            if self.documentVersion == version, !self.figures.isEmpty,
               abs(self.bounds.width - width) <= 0.5,
               case .success(let value) = result, let height = value as? NSNumber {
                let measured = CGFloat(height.doubleValue)
                if measured.isFinite, measured >= 0 {
                    self.renderedHeight = measured
                    self.setContentHeight(measured)
                }
            }
            // A resize or document change while the query was in flight gets
            // one fresh query; stale heights never alter the new document.
            if self.measurementRequested { self.requestHeightMeasurement() }
        }
    }

    private func setContentHeight(_ height: CGFloat) {
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
        invalidateIntrinsicContentSize()
        onHeightChanged()
    }
}

private final class InlineTextbookWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

private final class InlineTextbookRenderer: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
    static let scheme = "coretype-inline"
    var assets: [String: URL] = [:]
    var loaded = false
    var navigation: WKNavigation?
    var onLoad: () -> Void = {}

    func document(figures: [TextbookFigure], catalogue: FigureCatalogue, root: URL, version: Int) -> String {
        var sections: [String] = []
        for figure in figures {
            var contents: [String] = []
            for asset in figure.assets {
                guard let url = catalogue.assetURL(asset, root: root) else {
                    contents.append("<p class=\"unavailable\">This source file is unavailable.</p>")
                    continue
                }
                if asset.kind == "table" {
                    // These bundled fragments retain the source table's cells,
                    // headings and spans. Active content is removed by import.
                    if let fragment = try? String(contentsOf: url, encoding: .utf8) {
                        contents.append("<div class=\"table-scroll\">\(fragment)</div>")
                    } else {
                        contents.append("<p class=\"unavailable\">This source table is unavailable.</p>")
                    }
                } else {
                    let key = "asset-\(version)-\(assets.count).\(url.pathExtension.lowercased())"
                    assets[key] = url
                    contents.append("<img alt=\"\(escape(asset.alt))\" src=\"\(Self.scheme)://asset/\(key)\">")
                }
            }
            var credit = ""
            if !figure.attribution.isEmpty { credit += "<p class=\"credit\">\(escape(figure.attribution))</p>" }
            let book = figure.book == "microeconomics" ? "Microeconomics" : "Macroeconomics"
            if !figure.source.isEmpty { credit += "<p class=\"source\">\(book) · \(escape(figure.source))</p>" }
            sections.append("<figure>\(contents.joined())<figcaption>\(escape(figure.caption))</figcaption>\(credit)</figure>")
        }
        let license = figures.isEmpty ? "" : "<p class=\"license\">The CORE Econ Team · The Economy 2.0 · CC BY-NC-ND 4.0</p>"
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(Self.scheme): data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none';">
        <style>
        html,body{margin:0;background:\(Palette.panelHTML);color:\(Palette.textHTML);font-family:\(Typography.htmlFontFamily);overflow-y:hidden}
        main{display:flow-root;padding:0 0 24px}
        figure{margin:0 0 32px;overflow-wrap:anywhere}
        figure:last-of-type{margin-bottom:20px}
        img{display:block;width:100%;height:auto;background:white;margin:0 0 16px}
        figcaption{font-size:14px;line-height:1.5;font-weight:bold;margin:12px 0 7px}
        p{margin:0 0 .5em}p:last-child{margin-bottom:0}
        .credit{font-size:12px;line-height:1.5;color:\(Palette.mutedHTML);white-space:pre-line}
        .source,.license{font-size:11px;line-height:1.5;color:\(Palette.mutedHTML);overflow-wrap:anywhere}
        .license{margin:0}
        .unavailable{font-size:13px;color:\(Palette.mutedHTML)}
        .table-scroll{overflow-x:auto;overflow-y:hidden;margin:0 0 16px;color:#18212a;background:white}
        .table-scroll::-webkit-scrollbar{height:12px}
        .table-scroll::-webkit-scrollbar-track{background:#e3e8eb}
        .table-scroll::-webkit-scrollbar-thumb{background:#7a8b94;border:2px solid #e3e8eb;border-radius:6px}
        table{border-collapse:collapse;table-layout:auto;width:100%;min-width:520px;font-size:15px;line-height:1.45}
        th,td{padding:.6em .75em;border:1px solid #c5cbd1;vertical-align:top;overflow-wrap:break-word}
        th{font-weight:bold;text-align:left;background:#eef1f4}
        .align-left{text-align:left}.align-right,.data-align-right{text-align:right}.align-center{text-align:center}
        .vertical-align-middle,.vertical-align-center{vertical-align:middle}
        .table-subhead{font-weight:bold;background:#eef1f4}
        .slide-caption{font-size:14px;line-height:1.5;padding:12px}
        sup,sub{line-height:0}
        </style></head><body><main id="textbook">\(sections.joined())\(license)</main></body></html>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url, requestURL.scheme == Self.scheme,
              requestURL.host == "asset", let url = assets[requestURL.lastPathComponent] else {
            task.didFailWithError(URLError(.unsupportedURL)); return
        }
        do {
            let data = try Data(contentsOf: url)
            let mime = url.pathExtension.lowercased() == "svg" ? "image/svg+xml" : url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            task.didReceive(URLResponse(url: requestURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        } catch { task.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, navigation === self.navigation else { return }
        loaded = true
        onLoad()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
    }
}
