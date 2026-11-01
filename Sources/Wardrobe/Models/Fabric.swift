import Foundation

/// The weave or finish of a piece. Drives the texture drawn on illustrations and
/// swatches, and the "texture mix" note in the outfit builder.
enum Fabric: String, Codable, CaseIterable, Identifiable {
    case unknown
    case jersey, oxford, poplin, silk, satin
    case fineKnit, chunkyKnit, waffle, fleece
    case denim, twill, canvas, corduroy, tweed
    case linen, melton
    case leather, pebbledLeather, suede
    case technical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: return "Not set"
        case .jersey: return "Jersey"
        case .oxford: return "Oxford weave"
        case .poplin: return "Poplin"
        case .silk: return "Silk"
        case .satin: return "Satin"
        case .fineKnit: return "Fine knit"
        case .chunkyKnit: return "Chunky knit"
        case .waffle: return "Waffle knit"
        case .fleece: return "Fleece"
        case .denim: return "Denim"
        case .twill: return "Twill"
        case .canvas: return "Canvas"
        case .corduroy: return "Corduroy"
        case .tweed: return "Tweed"
        case .linen: return "Linen"
        case .melton: return "Melton wool"
        case .leather: return "Smooth leather"
        case .pebbledLeather: return "Pebbled leather"
        case .suede: return "Suede"
        case .technical: return "Technical"
        }
    }

    /// Whether the surface reads as visibly textured next to other pieces.
    var isTextured: Bool {
        switch self {
        case .fineKnit, .chunkyKnit, .waffle, .fleece, .denim, .twill, .canvas, .corduroy, .tweed, .pebbledLeather:
            return true
        case .unknown, .jersey, .oxford, .poplin, .silk, .satin, .linen, .melton, .leather, .suede, .technical:
            return false
        }
    }

    /// Whether the surface has a sheen (drawn with a stronger highlight).
    var isLustrous: Bool {
        self == .silk || self == .satin || self == .leather || self == .technical
    }

    /// Picks the most likely fabric from free text such as a product title,
    /// a material line ("100% cotton canvas") or a description.
    static func guess(from text: String) -> Fabric? {
        let t = text.lowercased()
        let rules: [(Fabric, [String])] = [
            (.waffle, ["waffle"]),
            (.corduroy, ["corduroy", "cord trouser", "cords"]),
            (.chunkyKnit, ["chunky", "cable knit", "cable-knit", "fisherman", "shetland"]),
            (.tweed, ["tweed", "herringbone", "boucle", "bouclé"]),
            (.denim, ["denim", "jean", "selvedge", "selvage", "chambray"]),
            (.oxford, ["oxford"]),
            (.poplin, ["poplin", "broadcloth"]),
            (.twill, ["twill", "chino", "gabardine", "cavalry"]),
            (.canvas, ["canvas", "duck"]),
            (.linen, ["linen", "flax"]),
            (.melton, ["melton", "overcoat", "boiled wool", "loden", "wool coat"]),
            (.suede, ["suede", "nubuck"]),
            (.pebbledLeather, ["pebbled", "pebble grain", "grained leather", "scotch grain"]),
            (.leather, ["leather", "calfskin", "patent"]),
            (.fleece, ["fleece", "sherpa", "polar"]),
            (.satin, ["satin", "sateen"]),
            (.silk, ["silk"]),
            (.fineKnit, ["merino", "cashmere", "knit", "sweater", "jumper", "cardigan", "crewneck", "lambswool"]),
            (.technical, ["nylon", "gore-tex", "goretex", "ripstop", "technical", "softshell", "shell", "waterproof"]),
            (.jersey, ["jersey", "t-shirt", "tee", "tank", "modal", "interlock", "pique", "piqué"]),
        ]
        for (fabric, words) in rules where words.contains(where: { t.contains($0) }) {
            return fabric
        }
        return nil
    }
}
