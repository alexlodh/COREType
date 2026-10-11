import AppKit
import SwiftUI

// Use the property wrapper through an alias; the SDK's new @State macro needs
// an Xcode-only plugin that is absent from Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Typography {
    static let htmlFontFamily = "Arial,sans-serif"
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .semibold || weight == .bold ? "Arial-BoldMT" : "ArialMT", size: size)
    }

    static func passageFont(size: CGFloat) -> NSFont {
        NSFont(name: "ArialMT", size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

enum Palette {
    static let panelHTML = "#1b2327"
    static let textHTML = "#e0e5de"
    static let mutedHTML = "#87999f"
    static let textColor = NSColor(red: 0.88, green: 0.9, blue: 0.87, alpha: 1)
    static let untypedColor = NSColor(red: 0.45, green: 0.49, blue: 0.53, alpha: 1)
    static let errorColor = NSColor(red: 1, green: 0.42, blue: 0.45, alpha: 1)
    static let background = Color(red: 0.067, green: 0.09, blue: 0.11)
    static let sidebar = Color(red: 0.087, green: 0.115, blue: 0.134)
    static let panel = Color(red: 0.105, green: 0.136, blue: 0.153)
    static let accent = Color(red: 0.95, green: 0.73, blue: 0.42)
    static let text = Color(red: 0.88, green: 0.90, blue: 0.87)
    static let muted = Color(red: 0.53, green: 0.6, blue: 0.63)
    static let green = Color(red: 0.52, green: 0.78, blue: 0.66)
}

