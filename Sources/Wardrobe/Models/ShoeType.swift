import Foundation

/// What kind of shoe a pair is. Shoes use this in place of a silhouette.
enum ShoeType: String, Codable, CaseIterable, Identifiable {
    case unknown
    case sneakers, running, formal, loafers, boots, sandals, heels, flats, slippers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: return "Not set"
        case .sneakers: return "Sneakers"
        case .running: return "Running"
        case .formal: return "Formal"
        case .loafers: return "Loafers"
        case .boots: return "Boots"
        case .sandals: return "Sandals"
        case .heels: return "Heels"
        case .flats: return "Flats"
        case .slippers: return "Slippers"
        }
    }

    /// Picks the type from a product title or breadcrumbs ("Suede Chelsea Boot").
    static func guess(from text: String) -> ShoeType? {
        let t = text.lowercased().replacingOccurrences(of: "-", with: " ")
        let rules: [(ShoeType, [String])] = [
            (.running, ["running", "runner", "trail shoe", "training shoe", "trainer"]),
            (.loafers, ["loafer", "moccasin", "penny", "driving shoe"]),
            (.boots, ["boot", "chelsea", "chukka"]),
            (.sandals, ["sandal", "slide", "flip flop", "espadrille", "clog"]),
            (.heels, ["heel", "pump", "stiletto", "slingback"]),
            (.flats, ["ballet", "flat", "mary jane"]),
            (.slippers, ["slipper"]),
            (.formal, ["oxford shoe", "oxfords", "derby", "brogue", "monk strap", "dress shoe", "wingtip", "cap toe"]),
            (.sneakers, ["sneaker", "trainer", "plimsoll", "high top", "low top", "skate shoe", "canvas shoe", "court shoe"]),
        ]
        for (type, words) in rules where words.contains(where: { t.contains($0) }) {
            return type
        }
        return nil
    }
}
