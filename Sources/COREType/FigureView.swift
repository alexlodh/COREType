import SwiftUI
import WebKit
import TypingCore

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
                Text("Textbook figures").font(Typography.font(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss(); model.focus() }.keyboardShortcut(.defaultAction)
            }
            if let figure = selected {
                HStack {
                    if model.currentFigures.count > 1 {
                        Picker("Figure", selection: $selectedID) {
                            ForEach(model.currentFigures) { f in Text(figureLabel(f)).tag(f.id) }
                        }.frame(width: 320).onChange(of: selectedID) { panel = 0; zoom = 1 }
                    } else { Text(figureLabel(figure)).font(Typography.font(size: 14, weight: .semibold)) }
                    Spacer()
                    Button("−") { zoom = max(1, zoom - 0.5) }.disabled(zoom == 1).accessibilityLabel("Zoom out")
                    Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 45)
                    Button("+") { zoom = min(3, zoom + 0.5) }.disabled(zoom == 3).accessibilityLabel("Zoom in")
                    Button("Fit") { zoom = 1 }.disabled(zoom == 1)
                }
                let asset = figure.assets.indices.contains(panel) ? figure.assets[panel] : figure.assets.first
                if let asset, let url = model.figureCatalogue.assetURL(asset, root: model.resourceRoot) {
                    LocalDiagram(url: url, alt: asset.alt, zoom: zoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 300)
                        .accessibilityLabel("Diagram \(figure.number)")
                    if figure.assets.count > 1 {
                        HStack {
                            Button("Previous panel") { panel -= 1; zoom = 1 }.disabled(panel == 0)
                            Spacer()
                            Text(asset.label.isEmpty ? "Panel \(panel + 1) of \(figure.assets.count)" : asset.label)
                            Spacer()
                            Button("Next panel") { panel += 1; zoom = 1 }.disabled(panel + 1 >= figure.assets.count)
                        }
                    }
                } else { Text("This diagram file is unavailable.").frame(maxWidth: .infinity, maxHeight: .infinity) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(figure.caption).font(Typography.font(size: 14, weight: .semibold))
                        if !figure.attribution.isEmpty { Text(figure.attribution).font(Typography.font(size: 12)) }
                        Text(figure.source).font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                        Text("The CORE Econ Team · The Economy 2.0 · CC BY-NC-ND 4.0\nOriginal diagrams · Noncommercial use · Full attribution in Credits and help")
                            .font(Typography.font(size: 11)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 115)
            } else { Text("This passage has no available diagrams.") }
        }.padding(24).frame(width: 900, height: 680)
            .font(Typography.font(size: 13)).foregroundStyle(Palette.text).background(Palette.background)
            .onAppear { selectedID = model.currentFigures.first?.id ?? "" }
            .onChange(of: model.current?.id) { selectedID = model.currentFigures.first?.id ?? ""; panel = 0; zoom = 1 }
    }
    func figureLabel(_ figure: TextbookFigure) -> String { "\(figure.book == "microeconomics" ? "Microeconomics" : "Macroeconomics") · Figure \(figure.number)" }
}

/// Serves one original bundled image. The HTML has no scripts and cannot load network resources.
private struct LocalDiagram: NSViewRepresentable {
    let url: URL
    let alt: String
    let zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "coretype-diagram")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.url != url || context.coordinator.zoom != zoom else { return }
        context.coordinator.url = url; context.coordinator.zoom = zoom
        let escapedAlt = alt.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src coretype-diagram: data:; style-src 'unsafe-inline';">
        <style>html,body{margin:0;width:100%;height:100%;background:white}img{display:block;object-fit:contain;width:\(zoom*100)%;height:\(zoom*100)%}</style>
        </head><body><img alt="\(escapedAlt)" src="coretype-diagram://asset/\(url.lastPathComponent)"></body></html>
        """, baseURL: nil)
    }
    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        var url: URL
        var zoom: Double = 0
        init(url: URL) { self.url = url }
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
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
