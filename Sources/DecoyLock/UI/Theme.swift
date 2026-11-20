import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// The owner-facing palette. Named after the possum the app is built around:
/// soft grey fur, a pink nose, the dusk it comes out in.
/// The password box an onlooker might see uses none of this; it stays system-plain.
enum Palette {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    /// Background of the mascot's stage.
    static let fur = dynamic(0xE9E5EF, 0x2A2632)
    /// Stage edge and quiet fills.
    static let furDeep = dynamic(0xD9D2E3, 0x3A3446)
    /// Primary text on the stage.
    static let ink = dynamic(0x2B2433, 0xF0EBF5)
    /// Secondary text and dashed outlines.
    static let dusk = dynamic(0x6B6285, 0xA9A0C4)
    /// Buttons and the one thing on screen you should press.
    static let action = dynamic(0xB13E66, 0xE57FA2)
    /// "It worked."
    static let moss = dynamic(0x4C6A42, 0x9CC08C)
    static let warning = Color(nsColor: .systemRed)

    // The mascot keeps its own colours in both modes; it's a character, not chrome.
    static let mascotFur = Color(nsColor: NSColor(hex: 0xF6F3F9))
    static let mascotShade = Color(nsColor: NSColor(hex: 0xDCD5E6))
    static let mascotInk = Color(nsColor: NSColor(hex: 0x2B2433))
    static let mascotNose = Color(nsColor: NSColor(hex: 0xEE86A6))
}

enum Fonts {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11.5)
}

/// The left-hand panel the mascot stands on.
struct Stage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Palette.fur.ignoresSafeArea()
            content
        }
        .overlay(alignment: .trailing) { Palette.furDeep.frame(width: 1) }
    }
}

/// A primary button in the app's own colour.
struct ActionButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(Palette.action)
            .controlSize(.large)
    }
}

extension View {
    func actionButton() -> some View { modifier(ActionButtonStyle()) }
}

/// The macOS "wrong password" wobble.
struct Shake: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}

/// SwiftUI's `State` property wrapper under another name. Newer SDKs also declare a
/// `@State` macro, and the Command Line Tools ship without its compiler plugin, so
/// `@State` fails to build there. An alias resolves straight to the property wrapper.
typealias ViewState<Value> = SwiftUI.State<Value>
