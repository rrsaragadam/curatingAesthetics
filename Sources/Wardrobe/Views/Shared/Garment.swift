import AppKit
import SwiftUI

// MARK: - SVG path parsing

/// A tiny parser for the absolute SVG path commands the garment outlines use
/// (M, L, H, V, Q, C, Z) in a 100×100 view box.
enum SVGPath {
    static func path(_ d: String, in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 100
        func pt(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        var tokens = tokenize(d)[...]
        var command: Character = "M"
        var current = CGPoint.zero
        func next() -> Double? {
            guard case .number(let n)? = tokens.first else { return nil }
            tokens.removeFirst()
            return n
        }
        while let token = tokens.first {
            if case .command(let c) = token { command = c; tokens.removeFirst() }
            switch command {
            case "M":
                guard let x = next(), let y = next() else { return path }
                current = CGPoint(x: x, y: y); path.move(to: pt(x, y)); command = "L"
            case "L":
                guard let x = next(), let y = next() else { return path }
                current = CGPoint(x: x, y: y); path.addLine(to: pt(x, y))
            case "H":
                guard let x = next() else { return path }
                current.x = x; path.addLine(to: pt(current.x, current.y))
            case "V":
                guard let y = next() else { return path }
                current.y = y; path.addLine(to: pt(current.x, current.y))
            case "Q":
                guard let cx = next(), let cy = next(), let x = next(), let y = next() else { return path }
                current = CGPoint(x: x, y: y); path.addQuadCurve(to: pt(x, y), control: pt(cx, cy))
            case "C":
                guard let c1x = next(), let c1y = next(), let c2x = next(), let c2y = next(),
                      let x = next(), let y = next() else { return path }
                current = CGPoint(x: x, y: y)
                path.addCurve(to: pt(x, y), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
            case "Z":
                path.closeSubpath()
                if case .number(_)? = tokens.first { tokens.removeFirst() }
            default:
                tokens.removeFirst()
            }
        }
        return path
    }

    private enum Token { case command(Character), number(Double) }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        func flush() {
            if let n = Double(buffer) { tokens.append(.number(n)) }
            buffer = ""
        }
        for ch in d {
            if ch.isLetter {
                flush(); tokens.append(.command(Character(ch.uppercased())))
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" && !buffer.isEmpty {
                flush(); buffer = "-"
            } else {
                buffer.append(ch)
            }
        }
        flush()
        return tokens
    }
}

// MARK: - Outlines

/// Hand-drawn outlines for each category, matching the mockup's illustrations.
enum GarmentOutline {
    static func body(for category: Category) -> String {
        switch category {
        case .top: return "M30 18 L42 12 Q50 20 58 12 L70 18 L82 34 L71 40 L68 35 L68 88 L32 88 L32 35 L29 40 L18 34 Z"
        case .bottom: return "M33 10 L67 10 L71 90 L56 90 L50 38 L44 90 L29 90 Z"
        case .jacket: return "M30 16 L43 12 L50 30 L57 12 L70 16 L84 72 L74 75 L68 42 L68 80 L32 80 L32 42 L26 75 L16 72 Z"
        case .outerwear: return "M30 14 L43 10 L50 30 L57 10 L70 14 L86 78 L75 81 L68 42 L68 90 L32 90 L32 42 L25 81 L14 78 Z"
        case .shoes: return "M12 66 L12 46 Q28 50 38 40 L52 56 Q70 59 87 63 Q90 72 85 75 L14 75 Z"
        case .accessory: return "M26 42 L74 42 L78 86 L22 86 Z M38 42 Q38 22 50 22 Q62 22 62 42 L58 42 Q58 27 50 27 Q42 27 42 42 Z"
        case .dress: return "M38 10 L44 8 Q50 14 56 8 L62 10 L60 34 Q72 60 78 90 L22 90 Q28 60 40 34 Z"
        }
    }

    static func details(for category: Category) -> String {
        switch category {
        case .top: return "M42 12 Q50 24 58 12 M32 36 Q35 27 30 18 M68 36 Q65 27 70 18 M33 83 L67 83"
        case .bottom: return "M33 17 L67 17 M50 17 L50 34 M36 17 Q37 25 44 25 M64 17 Q63 25 56 25 M31 84 L43 84 M57 84 L69 84"
        case .jacket: return "M43 12 L46 30 L50 30 M57 12 L54 30 L50 30 M50 30 L50 80 M36 56 L45 56 M55 56 L64 56 M32 74 L68 74"
        case .outerwear: return "M43 10 L45 38 L50 30 M57 10 L55 38 L50 30 M50 30 L50 90 M36 64 L45 64 M55 64 L64 64 M27 74 L24 76 M73 74 L76 76"
        case .shoes: return "M12 70 L86 70 M14 50 Q24 53 33 45 M38 46 L43 51 M42 43 L47 49 M46 47 L51 53"
        case .accessory: return "M24 52 L76 52 M48 52 L48 58 L52 58 L52 52"
        case .dress: return "M44 8 Q50 18 56 8 M40 34 L60 34 M26 84 L74 84"
        }
    }
}

struct OutlineShape: Shape {
    let d: String
    func path(in rect: CGRect) -> Path { SVGPath.path(d, in: rect) }
}

// MARK: - Fabric texture

/// Draws the weave of a fabric as a repeating pattern: ribs for knits, diagonal
/// twill lines for denim, a grid for canvas and oxford, speckle for suede.
struct FabricTexture: View {
    let fabric: Fabric
    /// The garment color, so marks are light on dark cloth and dark on light cloth.
    let baseHex: String
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let dark = (RGB(hex: baseHex)?.luminance ?? 0.5) < 0.18
            let ink = dark ? Color.white : Color.black
            let s = 5 * scale
            var marks = Path()
            var width: CGFloat = 0.8 * scale
            var opacity = 0.13

            func lines(every step: CGFloat, vertical: Bool) {
                var v: CGFloat = step / 2
                let limit = vertical ? size.width : size.height
                while v < limit {
                    if vertical {
                        marks.move(to: CGPoint(x: v, y: 0)); marks.addLine(to: CGPoint(x: v, y: size.height))
                    } else {
                        marks.move(to: CGPoint(x: 0, y: v)); marks.addLine(to: CGPoint(x: size.width, y: v))
                    }
                    v += step
                }
            }
            func diagonals(every step: CGFloat, rising: Bool) {
                var v: CGFloat = -size.height
                while v < size.width + size.height {
                    if rising {
                        marks.move(to: CGPoint(x: v, y: size.height)); marks.addLine(to: CGPoint(x: v + size.height, y: 0))
                    } else {
                        marks.move(to: CGPoint(x: v, y: 0)); marks.addLine(to: CGPoint(x: v + size.height, y: size.height))
                    }
                    v += step
                }
            }
            func dots(every step: CGFloat, radius: CGFloat, jitter: Bool) {
                var y: CGFloat = step / 2, row = 0
                while y < size.height {
                    var x: CGFloat = (jitter && row % 2 == 1) ? step : step / 2
                    while x < size.width {
                        marks.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                        x += step
                    }
                    y += step; row += 1
                }
            }

            var filled = false
            switch fabric {
            case .fineKnit: lines(every: s * 0.8, vertical: true); width = 1.1 * scale; opacity = 0.16
            case .chunkyKnit: lines(every: s * 1.6, vertical: true); lines(every: s * 2.4, vertical: false); width = 1.8 * scale; opacity = 0.14
            case .waffle: lines(every: s, vertical: true); lines(every: s, vertical: false); width = 1.2 * scale; opacity = 0.15
            case .denim: diagonals(every: s * 0.7, rising: true); opacity = dark ? 0.2 : 0.14
            case .twill: diagonals(every: s * 0.6, rising: false); width = 0.7 * scale; opacity = 0.12
            case .canvas, .oxford: lines(every: s * 0.5, vertical: true); lines(every: s * 0.5, vertical: false)
                width = 0.6 * scale; opacity = fabric == .canvas ? 0.13 : 0.08
            case .linen: lines(every: s * 0.5, vertical: false); lines(every: s * 0.9, vertical: true); width = 0.6 * scale; opacity = 0.09
            case .corduroy: lines(every: s * 0.9, vertical: true); width = 1.6 * scale; opacity = 0.18
            case .tweed: diagonals(every: s * 0.8, rising: true); diagonals(every: s * 0.8, rising: false); width = 0.8 * scale; opacity = 0.14
            case .jersey: dots(every: s * 0.6, radius: 0.35 * scale, jitter: true); filled = true; opacity = 0.14
            case .suede: dots(every: s * 0.4, radius: 0.3 * scale, jitter: true); filled = true; opacity = 0.18
            case .pebbledLeather: dots(every: s * 0.9, radius: 0.9 * scale, jitter: true); filled = true; opacity = 0.2
            case .fleece: dots(every: s * 0.7, radius: 0.7 * scale, jitter: true); filled = true; opacity = 0.12
            case .poplin: lines(every: s * 0.4, vertical: false); width = 0.4 * scale; opacity = 0.06
            case .melton, .leather, .silk, .satin, .technical, .unknown: break
            }
            if filled {
                ctx.fill(marks, with: .color(ink.opacity(opacity)))
            } else {
                ctx.stroke(marks, with: .color(ink.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Illustration

/// A piece drawn in its own color and fabric, for pieces without a photo.
struct GarmentIllustration: View {
    let category: Category
    let hex: String
    let fabric: Fabric
    var lineWidth: CGFloat = 1.3

    var body: some View {
        let outline = OutlineShape(d: GarmentOutline.body(for: category))
        let details = OutlineShape(d: GarmentOutline.details(for: category))
        GeometryReader { geo in
            let scale = max(0.6, geo.size.width / 160)
            ZStack {
                outline.fill(Color(hex: hex))
                FabricTexture(fabric: fabric, baseHex: hex, scale: scale).clipShape(outline)
                outline.fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(fabric.isLustrous ? 0.5 : 0.36), location: 0),
                        .init(color: .white.opacity(0), location: 0.45),
                        .init(color: .black.opacity(0.16), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                outline.stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                details.stroke(Color.black.opacity(0.24), style: StrokeStyle(lineWidth: lineWidth * 0.9, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The piece's cut-out photo, or its illustration when there's no photo.
struct GarmentView: View {
    @Environment(WardrobeStore.self) private var store
    let item: ClothingItem

    var body: some View {
        if let image = store.image(for: item) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityLabel(item.name)
        } else {
            GarmentIllustration(category: item.category, hex: item.colorHex, fabric: item.fabric)
                .accessibilityLabel(item.name)
        }
    }
}

/// A small square of color and texture.
struct FabricSwatch: View {
    let hex: String
    let fabric: Fabric
    var size: CGFloat = 14
    var corner: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color(hex: hex))
            .overlay { FabricTexture(fabric: fabric, baseHex: hex, scale: 0.7) }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.black.opacity(0.12)) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A horizontal bar of each piece's color, used on look cards and the week strip.
struct PaletteBar: View {
    let hexes: [String]
    var height: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                Rectangle().fill(Color(hex: hex))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(.black.opacity(0.08)) }
        .accessibilityHidden(true)
    }
}
