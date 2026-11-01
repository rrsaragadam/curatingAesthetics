import Foundation

/// A plain sRGB color with 0–1 components. Kept free of AppKit/SwiftUI so the
/// model layer stays simple to test.
struct RGB: Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var hex: String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    /// Hue in degrees 0–360, saturation and brightness 0–1.
    var hsb: (h: Double, s: Double, b: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0 {
            if maxV == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        return (h, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    /// Relative luminance (WCAG).
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// CIE L*a*b*, for perceptual color distance.
    var lab: (l: Double, a: Double, b: Double) {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(b)
        let x = (R * 0.4124 + G * 0.3576 + B * 0.1805) / 0.95047
        let y = (R * 0.2126 + G * 0.7152 + B * 0.0722)
        let z = (R * 0.0193 + G * 0.1192 + B * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : (7.787 * t + 16 / 116) }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    func distance(to other: RGB) -> Double {
        let a = lab, b = other.lab
        return sqrt(pow(a.l - b.l, 2) + pow(a.a - b.a, 2) + pow(a.b - b.b, 2))
    }
}

/// Broad color groups used by the closet's color strip.
enum ColorFamily: String, CaseIterable, Identifiable {
    case neutral, brown, blue, green, bright, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .neutral: return "Neutrals"
        case .brown: return "Browns"
        case .blue: return "Blues"
        case .green: return "Greens"
        case .bright: return "Brights"
        case .dark: return "Darks"
        }
    }

    static func of(hex: String) -> ColorFamily {
        guard let rgb = RGB(hex: hex) else { return .neutral }
        let (h, s, b) = rgb.hsb
        if b < 0.24 { return .dark }
        if s < 0.12 { return b < 0.32 ? .dark : .neutral }
        if (15...55).contains(h) {
            if s < 0.32 && b > 0.62 { return .neutral }   // sand, stone, oatmeal, camel-light
            if b < 0.75 { return .brown }
        }
        if (180...265).contains(h) { return .blue }
        if (65...180).contains(h) { return s < 0.18 && b > 0.6 ? .neutral : .green }
        return .bright
    }
}

/// Names a color the way you'd describe a garment ("Olive", not "#6E7B5B").
enum ColorNamer {
    static let palette: [(String, String)] = [
        ("White", "#FAFAF7"), ("Off-white", "#F1EEE6"), ("Cream", "#EFE6D2"), ("Ivory", "#F4EFE1"),
        ("Oatmeal", "#D9CBB0"), ("Sand", "#E2D3B5"), ("Stone", "#B8A88A"), ("Khaki", "#A89A72"),
        ("Camel", "#B98A55"), ("Tan", "#C19A6B"), ("Tobacco", "#8A5A35"), ("Cognac", "#9A4E24"),
        ("Brown", "#6B4A33"), ("Chocolate", "#4A3426"), ("Rust", "#A0462A"), ("Terracotta", "#C2583A"),
        ("Burgundy", "#6D1F2C"), ("Red", "#B3261E"), ("Coral", "#E57B62"), ("Pink", "#E7A9B4"),
        ("Blush", "#EBCFC6"), ("Mustard", "#C9A13B"), ("Yellow", "#E8C547"), ("Orange", "#D9732B"),
        ("Olive", "#6E7B5B"), ("Sage", "#9CAA8E"), ("Forest", "#2F4A39"), ("Green", "#3E7A4F"),
        ("Mint", "#BFDCCB"), ("Teal", "#2F6F73"), ("Pale blue", "#DCE6F2"), ("Sky", "#9DBBDB"),
        ("Light wash", "#8DA6C2"), ("Mid blue", "#4E6E98"), ("Indigo", "#3B4F6E"), ("Navy", "#1F2A44"),
        ("Cobalt", "#2449A8"), ("Lavender", "#B9AED6"), ("Purple", "#5D3F7A"), ("Light grey", "#C9C9C6"),
        ("Grey", "#8E8E8A"), ("Heather grey", "#A7A6A2"), ("Charcoal", "#2E2C2A"), ("Black", "#141414"),
    ]

    private static let parsed: [(String, RGB)] = palette.compactMap { name, hex in
        RGB(hex: hex).map { (name, $0) }
    }

    static func name(forHex hex: String) -> String {
        guard let rgb = RGB(hex: hex) else { return "Color" }
        return name(for: rgb)
    }

    static func name(for rgb: RGB) -> String {
        parsed.min { $0.1.distance(to: rgb) < $1.1.distance(to: rgb) }?.0 ?? "Color"
    }

    /// Looks up a store's color word ("Oatmeal Heather") against the palette.
    static func hex(forColorWord word: String) -> String? {
        let w = word.lowercased()
        let byLength = palette.sorted { $0.0.count > $1.0.count }
        if let hit = byLength.first(where: { w.contains($0.0.lowercased()) }) { return hit.1 }
        let extras: [(String, String)] = [
            ("ecru", "#EFE6D2"), ("bone", "#EFE6D2"), ("natural", "#E9DFC9"), ("beige", "#D8C7A6"),
            ("taupe", "#9C8C7A"), ("espresso", "#3B2A20"), ("walnut", "#5C4030"), ("chestnut", "#7B4A2E"),
            ("wine", "#6D1F2C"), ("maroon", "#5E1A25"), ("ochre", "#C08A2B"), ("gold", "#C9A13B"),
            ("army", "#5B6145"), ("moss", "#6B7449"), ("hunter", "#2F4A39"), ("emerald", "#2F7A55"),
            ("denim", "#4E6E98"), ("blue", "#4E6E98"), ("slate", "#5D6B78"), ("graphite", "#3A3A3A"),
            ("grey", "#8E8E8A"), ("gray", "#8E8E8A"), ("onyx", "#141414"), ("jet", "#141414"),
            ("lilac", "#B9AED6"), ("plum", "#5D3F7A"), ("rose", "#E7A9B4"), ("peach", "#F0B99A"),
        ]
        return extras.first(where: { w.contains($0.0) })?.1
    }
}
