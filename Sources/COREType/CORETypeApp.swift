import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.archive(reason: "App closed"); model?.save() }
}

@main struct CORETypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("COREType", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 740)
                .onAppear {
                    delegate.model = model
                    NSApp.windows.first?.backgroundColor = NSColor(red: 0.067, green: 0.09, blue: 0.11, alpha: 1)
                }
        }
        .defaultSize(width: 1260, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Practice") {
                Button("Repeat test") { model.restart() }.keyboardShortcut("r")
                Button("Next paragraph") { model.next() }.keyboardShortcut("n")
                Button("Pause / Resume") { model.pauseOrResume() }.keyboardShortcut("p")
                Divider()
                Button("Show practice") { model.navigate("practice") }.keyboardShortcut("1")
                Button("Show history") { model.navigate("history") }.keyboardShortcut("2")
                Button("Focus passage") { model.navigate("practice"); model.focus() }.keyboardShortcut("t")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.pause(); model.showingSettings = true }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .appInfo) {
                Button("Credits and help…") { model.pause(); model.showingInfo = true }
            }
        }
    }
}
