import Foundation

/// Why a stylist suggestion was turned down.
enum DeclineReason: String, Codable, CaseIterable, Identifiable {
    case notMyStyle, color, haveSimilar, tooFormal, tooCasual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notMyStyle: return "Not my style"
        case .color: return "Wrong color"
        case .haveSimilar: return "I have something like it"
        case .tooFormal: return "Too dressy"
        case .tooCasual: return "Too casual"
        }
    }

    /// How the reason reads in a prompt: "not their style".
    var phrase: String {
        switch self {
        case .notMyStyle: return "not their style"
        case .color: return "wrong color for them"
        case .haveSimilar: return "too close to something they own"
        case .tooFormal: return "too dressy"
        case .tooCasual: return "too casual"
        }
    }
}

/// What the stylist has learned from the suggestions you turned down, kept
/// with the library. Together with the closet itself it's the stylist's
/// picture of your taste.
struct StylistTaste: Codable, Hashable {
    struct DeclinedPiece: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var category: Category
        var colorName: String
        var fabric: Fabric
        var reason: DeclineReason
        var date: Date = .now
    }

    struct DeclinedLook: Codable, Hashable, Identifiable {
        var id = UUID()
        var itemIDs: [UUID]
        var reason: DeclineReason
        var date: Date = .now
    }

    var pieces: [DeclinedPiece] = []
    var looks: [DeclinedLook] = []

    var isEmpty: Bool { pieces.isEmpty && looks.isEmpty }
    var count: Int { pieces.count + looks.count }

    /// True when a suggested piece repeats one that was turned down, or
    /// matches it on what the reason was about: the same kind of piece in the
    /// same fabric for "not my style", the same color for "wrong color".
    func rules(out name: String, category: Category, colorName: String, fabric: Fabric) -> Bool {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        return pieces.contains { declined in
            if declined.name.lowercased().trimmingCharacters(in: .whitespaces) == key { return true }
            switch declined.reason {
            case .notMyStyle: return declined.category == category && declined.fabric == fabric && fabric != .unknown
            case .color: return declined.colorName.lowercased() == colorName.lowercased()
            case .haveSimilar: return declined.category == category
                && ColorFamily.of(hex: ColorNamer.palette.first { $0.0 == declined.colorName }?.1 ?? "")
                    == ColorFamily.of(hex: ColorNamer.palette.first { $0.0 == colorName }?.1 ?? "")
            case .tooFormal, .tooCasual: return false
            }
        }
    }

    /// "leaning dressier" when looks and pieces were turned down as too casual
    /// more often than too dressy, and the other way round.
    var formalityLean: String? {
        let reasons = pieces.map(\.reason) + looks.map(\.reason)
        let dressy = reasons.filter { $0 == .tooFormal }.count
        let casual = reasons.filter { $0 == .tooCasual }.count
        return casual > dressy ? "on the dressier side" : dressy > casual ? "on the relaxed side" : nil
    }

    func declined(look itemIDs: [UUID]) -> Bool {
        let set = Set(itemIDs)
        return looks.contains { Set($0.itemIDs) == set }
    }

    /// The pieces they turned down, newest first, as prompt lines.
    func pieceLines(limit: Int = 12) -> [String] {
        pieces.suffix(limit).reversed().map { "\($0.name) (\($0.reason.phrase))" }
    }

    /// Patterns worth stating outright, such as a color they turned down.
    var leanings: [String] {
        var lines: [String] = []
        lines += Set(pieces.filter { $0.reason == .color }.map { $0.colorName.lowercased() }).sorted().map { "avoid \($0)" }
        if let formalityLean { lines.append("keep it \(formalityLean)") }
        return lines
    }
}
