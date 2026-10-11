import SwiftUI
import WebKit
import TypingCore

enum TextbookAssetLabel {
    static func label(for figure: TextbookFigure, includeBook: Bool = false) -> String {
        let name = figure.namespace == "table" ? "Table" : "Figure"
        let type = figure.namespace != "table" && figure.isTable ? " · Table" : ""
        let book = includeBook ? "\(figure.book == "microeconomics" ? "Microeconomics" : "Macroeconomics") · " : ""
        return "\(book)\(name) \(figure.number)\(type)"
    }

    static func groupLabel(_ figures: [TextbookFigure]) -> String {
        if figures.count == 1 { return label(for: figures[0]) }
        let name = figures.allSatisfy(\.isTable) ? "Tables" : figures.contains(where: \.isTable) ? "Figures and tables" : "Figures"
        return "\(name) (\(figures.count))"
    }
}

struct FigureView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selectedID = ""
    @ViewState private var panel = 0
    @ViewState private var zoom = 1.0
    var selected: TextbookFigure? { model.currentFigures.first { $0.id == selectedID } ?? model.currentFigures.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Textbook figures and tables").font(Typography.font(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss(); model.focus() }.keyboardShortcut(.defaultAction)
            }
            if let figure = selected {
                HStack {
                    if model.currentFigures.count > 1 {
                        Picker("Figure or table", selection: $selectedID) {
                            ForEach(model.currentFigures) { f in Text(TextbookAssetLabel.label(for: f, includeBook: true)).tag(f.id) }
                        }.frame(width: 320).onChange(of: selectedID) { panel = 0; zoom = 1 }
                    } else { Text(TextbookAssetLabel.label(for: figure, includeBook: true)).font(Typography.font(size: 14, weight: .semibold)) }
                    Spacer()
                    Button("−") { zoom = max(1, zoom - 0.5) }.disabled(zoom == 1).accessibilityLabel("Zoom out")
                    Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 45)
                    Button("+") { zoom = min(3, zoom + 0.5) }.disabled(zoom == 3).accessibilityLabel("Zoom in")
                    Button("Fit") { zoom = 1 }.disabled(zoom == 1)
                }
                let asset = figure.assets.indices.contains(panel) ? figure.assets[panel] : figure.assets.first
                if let asset, let url = model.figureCatalogue.assetURL(asset, root: model.resourceRoot) {
                    LocalTextbookAsset(url: url, kind: asset.kind, alt: asset.alt, zoom: zoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 300)
                        .accessibilityLabel(TextbookAssetLabel.label(for: figure))
                    if figure.assets.count > 1 {
                        HStack {
                            Button("Previous panel") { panel -= 1; zoom = 1 }.disabled(panel == 0)
                            Spacer()
                            Text(asset.label.isEmpty ? "Panel \(panel + 1) of \(figure.assets.count)" : asset.label)
                            Spacer()
                            Button("Next panel") { panel += 1; zoom = 1 }.disabled(panel + 1 >= figure.assets.count)
                        }
                    }
                } else { Text("This figure or table file is unavailable.").frame(maxWidth: .infinity, maxHeight: .infinity) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(figure.caption).font(Typography.font(size: 14, weight: .semibold))
                        if !figure.attribution.isEmpty { Text(figure.attribution).font(Typography.font(size: 12)) }
                        Text(figure.source).font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                        Text("The CORE Econ Team · The Economy 2.0 · CC BY-NC-ND 4.0\nOriginal figures and tables · Noncommercial use · Full attribution in Credits and help")
                            .font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 115)
            } else { Text("This passage has no available figures or tables.") }
        }.padding(24).frame(width: 900, height: 680)
            .font(Typography.font(size: 13)).foregroundStyle(Palette.text).background(Palette.background)
            .onAppear { selectedID = model.currentFigures.first?.id ?? "" }
            .onChange(of: model.current?.id) { selectedID = model.currentFigures.first?.id ?? ""; panel = 0; zoom = 1 }
    }
}

/// Displays an original image or sanitized source table using bundled files only.
/// JavaScript, remote resources, and external navigation are disabled.
private struct LocalTextbookAsset: NSViewRepresentable {
    let url: URL
    let kind: String
    let alt: String
    let zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "coretype-diagram")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.url != url || context.coordinator.zoom != zoom || context.coordinator.kind != kind else { return }
        context.coordinator.url = url; context.coordinator.zoom = zoom; context.coordinator.kind = kind
        let stylesheet: String
        let content: String
        if kind == "table" {
            // The importer keeps semantic source markup and removes active content.
            // assetURL has already constrained this file to the bundled Tables directory.
            let fragment = (try? String(contentsOf: url, encoding: .utf8)) ?? "<p>The table could not be loaded.</p>"
            stylesheet = """
            html,body{margin:0;min-height:100%;background:white;color:#18212a;font-family:Arial,sans-serif}
            body{overflow:auto}.table-content{padding:16px;box-sizing:border-box}
            table{border-collapse:collapse;table-layout:auto;width:\(zoom*100)%;min-width:\(620*zoom)px;font-size:\(16*zoom)px;line-height:1.45}
            th,td{padding:.6em .75em;border:1px solid #c5cbd1;vertical-align:top;overflow-wrap:break-word}
            th{font-weight:bold;text-align:left;background:#eef1f4}
            .align-left{text-align:left}.align-right,.data-align-right{text-align:right}.align-center{text-align:center}
            .vertical-align-middle,.vertical-align-center{vertical-align:middle}
            .table-subhead{font-weight:bold;background:#eef1f4}
            p{margin:0 0 .5em}p:last-child{margin-bottom:0}sup,sub{line-height:0}
            """
            content = "<div class=\"table-content\">\(fragment)</div>"
        } else {
            let escapedAlt = alt.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
            stylesheet = "html,body{margin:0;width:100%;height:100%;background:white}img{display:block;object-fit:contain;width:\(zoom*100)%;height:\(zoom*100)%}"
            content = "<img alt=\"\(escapedAlt)\" src=\"coretype-diagram://asset/\(url.lastPathComponent)\">"
        }
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src coretype-diagram: data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none';">
        <style>\(stylesheet)</style>
        </head><body>\(content)</body></html>
        """, baseURL: nil)
    }
    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        var url: URL
        var zoom: Double = 0
        var kind = ""
        init(url: URL) { self.url = url }
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard kind != "table", urlSchemeTask.request.url?.lastPathComponent == url.lastPathComponent else {
                urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
            }
            do {
                let data = try Data(contentsOf: url)
                let mime = url.pathExtension.lowercased() == "svg" ? "image/svg+xml" : url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
                let response = URLResponse(url: urlSchemeTask.request.url!, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
                urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
            } catch { urlSchemeTask.didFailWithError(error) }
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme
            decisionHandler(scheme == "about" || scheme == "coretype-diagram" ? .allow : .cancel)
        }
    }
}
