import Foundation

/// The cut of a piece: how it sits on the body. Read from a product page's fit
/// details when there are any, and set by hand otherwise.
enum Silhouette: String, Codable, CaseIterable, Identifiable {
    case unknown
    case slim, fitted, regular, straight, relaxed, boxy, oversized
    case cropped, tapered, barrel, wideLeg, bootcut, flared, aLine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: return "Not set"
        case .slim: return "Slim"
        case .fitted: return "Fitted"
        case .regular: return "Regular"
        case .straight: return "Straight"
        case .relaxed: return "Relaxed"
        case .boxy: return "Boxy"
        case .oversized: return "Oversized"
        case .cropped: return "Cropped"
        case .tapered: return "Tapered"
        case .barrel: return "Barrel"
        case .wideLeg: return "Wide leg"
        case .bootcut: return "Bootcut"
        case .flared: return "Flared"
        case .aLine: return "A-line"
        }
    }

    /// Picks the cut from free text such as a product title ("Wide-Leg Pleated
    /// Trouser") or description ("a relaxed fit"). Only fit phrases count there,
    /// so "slim pocket" or "a relaxed weekend" don't match. A store's own
    /// "Silhouette:" or "Fit:" value is `labeled`, where a bare "Straight" or
    /// "Loose" is enough.
    static func guess(from text: String, labeled: Bool = false) -> Silhouette? {
        let t = text.lowercased().replacingOccurrences(of: "-", with: " ")
        let rules: [(Silhouette, [String])] = [
            (.barrel, ["barrel", "horseshoe", "curved leg", "balloon leg"]),
            (.wideLeg, ["wide leg", "wide fit", "wide pants", "wide pant", "wide trousers", "wide trouser", "wide jeans", "palazzo"]),
            (.bootcut, ["bootcut", "boot cut"]),
            (.flared, ["flared", "flare leg", "flare fit"]),
            (.aLine, ["a line"]),
            (.tapered, ["tapered", "taper fit", "carrot fit"]),
            (.oversized, ["oversized", "oversize fit", "loose fit", "dropped shoulder", "drop shoulder"]),
            (.boxy, ["boxy"]),
            (.cropped, ["cropped"]),
            (.relaxed, ["relaxed fit", "relaxed leg", "easy fit", "baggy"]),
            (.straight, ["straight leg", "straight fit", "straight cut"]),
            (.slim, ["slim fit", "slim leg", "skinny", "slim straight", "slim cut"]),
            (.fitted, ["fitted", "tailored fit", "body fit", "muscle fit"]),
            (.regular, ["regular fit", "classic fit", "standard fit"]),
        ]
        for (silhouette, phrases) in rules where phrases.contains(where: { matches(t, $0) }) {
            return silhouette
        }
        guard labeled else { return nil }
        let words: [(Silhouette, [String])] = [
            (.wideLeg, ["wide"]), (.relaxed, ["relaxed", "loose", "easy"]), (.straight, ["straight"]),
            (.slim, ["slim", "narrow"]), (.regular, ["regular", "classic", "standard"]),
            (.oversized, ["oversize"]), (.fitted, ["tailored"]),
        ]
        for (silhouette, list) in words where list.contains(where: { matches(t, $0) }) {
            return silhouette
        }
        return nil
    }

    /// Whole-word match, so "slim" doesn't fire inside "slimline".
    private static func matches(_ text: String, _ phrase: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", options: .regularExpression) != nil
    }
}
