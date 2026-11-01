import AppKit
import CoreText
import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: String) {
        let rgb = RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    /// A color that follows the window's light/dark appearance.
    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = RGB(hex: isDark ? dark : light) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
    }
}

/// The palette from the approved mockup: a deep forest sidebar, a warm-neutral
/// ground that keeps garment colors true, and a linen board under outfits.
enum Theme {
    // Sidebar (stays dark in both appearances)
    static let forest = Color(hex: "#1D2A23")
    static let forestRaised = Color(hex: "#26362D")
    static let forestText = Color(hex: "#DCE5DE")
    static let forestMuted = Color(hex: "#93A699")
    static let mint = Color(hex: "#A8D5B5")

    // Content
    static let ground = Color.dynamic(light: "#F7F6F3", dark: "#171917")
    static let card = Color.dynamic(light: "#FFFFFF", dark: "#22241F")
    static let panel = Color.dynamic(light: "#FFFFFF", dark: "#1D1F1B")
    static let linen = Color.dynamic(light: "#EFECE5", dark: "#2A2924")
    static let linenDeep = Color.dynamic(light: "#E5E1D7", dark: "#33322C")
    static let ink = Color.dynamic(light: "#1C1C1A", dark: "#ECEBE6")
    static let inkSecondary = Color.dynamic(light: "#5E5E58", dark: "#A9A8A1")
    static let inkTertiary = Color.dynamic(light: "#6B6B65", dark: "#8E8D86")
    static let line = Color.dynamic(light: "#E6E4DE", dark: "#34362F")
    static let hover = Color.dynamic(light: "#EFEEEA", dark: "#2B2D28")

    // Accents
    static let green = Color.dynamic(light: "#3E5A47", dark: "#7FAE8C")
    static let greenPressed = Color.dynamic(light: "#344D3C", dark: "#93C0A0")
    static let onGreen = Color.dynamic(light: "#FFFFFF", dark: "#10180F")
    static let greenTonal = Color.dynamic(light: "#E3EAE4", dark: "#2A3A2F")
    static let greenTonalHover = Color.dynamic(light: "#D6E0D8", dark: "#33473A")
    static let clay = Color(hex: "#C2583A")
    static let amber = Color.dynamic(light: "#8A5A10", dark: "#E2B565")
    static let amberTonal = Color.dynamic(light: "#F6EBD6", dark: "#3A3020")
}

// MARK: - Type

/// Bricolage Grotesque for headings and numbers; the system font for everything else.
enum Typeface {
    static func registerBundledFonts() {
        let urls = ["ttf", "woff2"].flatMap { Bundle.module.urls(forResourcesWithExtension: $0, subdirectory: "Fonts") ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat, bold: Bool = true) -> Font {
        // Geist Serif comes in one weight; a touch larger keeps headings as strong.
        if NSFont(name: "GeistSerif-Regular", size: size) != nil {
            return .custom("GeistSerif-Regular", size: (size * 1.1).rounded())
        }
        let name = bold ? "BricolageGrotesque-Bold" : "BricolageGrotesque-SemiBold"
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: bold ? .bold : .semibold, design: .rounded)
    }
}

extension Font {
    static var wardrobeTitle: Font { Typeface.display(30) }
    static var wardrobeHeading: Font { Typeface.display(20) }
    static var wardrobeSubheading: Font { Typeface.display(15, bold: false) }
}

// MARK: - Motion

enum Motion {
    static let lift = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.68)
    static let quick = Animation.easeOut(duration: 0.15)

    /// Returns nil when Reduce Motion is on, so `withAnimation` falls back to a cut.
    static func respecting(_ reduce: Bool, _ animation: Animation) -> Animation? {
        reduce ? .easeInOut(duration: 0.12) : animation
    }
}

// MARK: - Buttons

struct WardrobeButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet, tonal, dark }
    var kind: Kind = .quiet
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, compact: compact)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, compact ? 10 : 14)
                .frame(minHeight: compact ? 30 : 36)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if kind == .quiet {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Motion.quick, value: hovering)
                .animation(Motion.quick, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: return Theme.onGreen
            case .dark: return Theme.forestText
            case .tonal: return Theme.green
            case .quiet: return Theme.ink
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return hovering ? Theme.greenPressed : Theme.green
            case .dark: return hovering ? Theme.forestRaised : Theme.forest
            case .tonal: return hovering ? Theme.greenTonalHover : Theme.greenTonal
            case .quiet: return hovering ? Theme.hover : Theme.card
            }
        }
    }
}

extension ButtonStyle where Self == WardrobeButtonStyle {
    static var primary: WardrobeButtonStyle { WardrobeButtonStyle(kind: .primary) }
    static var quiet: WardrobeButtonStyle { WardrobeButtonStyle(kind: .quiet) }
    static var tonal: WardrobeButtonStyle { WardrobeButtonStyle(kind: .tonal) }
    static var dark: WardrobeButtonStyle { WardrobeButtonStyle(kind: .dark) }
}

/// A pill used for filters (categories, occasions, sizes).
struct ChipToggle: View {
    let label: String
    var count: Int?
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Theme.onGreen.opacity(0.75) : Theme.inkTertiary)
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(isOn ? Theme.onGreen : Theme.ink)
            .background(isOn ? Theme.green : (hovering ? Theme.hover : Theme.card), in: Capsule())
            .overlay { if !isOn { Capsule().strokeBorder(Theme.line) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.lift, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Small label/value rows used in detail panels.
struct DetailRow: View {
    let label: String
    let value: String
    var swatch: AnyView?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 6) {
                if let swatch { swatch }
                Text(value.isEmpty ? "Not set" : value)
                    .foregroundStyle(value.isEmpty ? Theme.inkTertiary : Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
    }
}
