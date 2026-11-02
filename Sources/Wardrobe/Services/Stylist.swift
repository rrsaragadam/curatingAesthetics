import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One outfit the stylist put together from pieces you own.
struct StylistLook: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var itemIDs: [UUID]
    var why: String
    /// True when the model's raw answer broke a rule (an unknown piece, two
    /// tops, no shoes) and the look was repaired before showing it.
    var wasRepaired = false
}

/// A piece you don't own yet that fits your style and works with what you have.
struct StylistGap: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: Category
    var colorHex: String
    var fabric: Fabric
    var why: String
    /// Pieces you own that it would be worn with.
    var pairsWith: [UUID]
}

/// The stylist's read of a closet: its style in a sentence, and what's missing.
struct StylistGaps: Hashable {
    var style: String
    var pieces: [StylistGap]
}

/// The hook for a stylist. The sidebar card and the builder's "This look"
/// panel are where its answers show up.
protocol Stylist {
    /// Complete outfits for an occasion, built only from `closet`. Every look
    /// includes `keeping` (pieces locked in the builder) and steers clear of
    /// combinations `taste` says were turned down.
    func suggest(from closet: [ClothingItem], saved: [Outfit], taste: StylistTaste, occasion: Occasion, season: Season,
                 keeping: [ClothingItem], count: Int) async throws -> [StylistLook]

    /// Short, specific feedback on a combination ("swap the loafers for the
    /// sneakers to match the canvas jacket").
    func critique(outfit: [ClothingItem], occasion: Occasion, closet: [ClothingItem]) async throws -> String

    /// Pieces that fit your style (the closet plus what `taste` says was
    /// turned down) and would unlock the most new outfits from what you own.
    func gaps(in closet: [ClothingItem], outfits: [Outfit], taste: StylistTaste) async throws -> StylistGaps
}

enum StylistProvider {
    /// The on-device stylist when Apple Intelligence is ready, else nil.
    static var current: Stylist? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.isAvailable { return OnDeviceStylist() }
        #endif
        return nil
    }

    /// Why `current` is nil, in words for the sidebar card.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use the stylist."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading. Try again in a little while."
            case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
            case .unavailable: return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "The stylist needs macOS 26 with Apple Intelligence."
    }
}

// MARK: - Closet as text

enum StylistCatalog {
    /// A piece's details for a language model, after its name and color:
    /// "top | fine knit | 100% merino wool | slim fit | smart casual | fall, winter".
    static func details(for item: ClothingItem) -> String {
        var parts = [item.category.singular.lowercased()]
        if item.category == .shoes, item.shoeType != .unknown { parts.append(item.shoeType.label.lowercased()) }
        if item.fabric != .unknown { parts.append(item.fabric.label.lowercased()) }
        if !item.material.isEmpty { parts.append(item.material) }
        if item.silhouette != .unknown { parts.append(item.silhouette.label.lowercased() + " fit") }
        parts.append(item.formality.label.lowercased())
        parts.append(Season.describe(item.seasons).lowercased())
        let tags = item.tags.filter { $0 != SampleCloset.tag }
        if !tags.isEmpty { parts.append("tags: " + tags.joined(separator: ", ")) }
        return parts.joined(separator: " | ")
    }
}

/// Turns a model's list of pieces into a wearable outfit: known pieces only,
/// one per slot, with a top (or dress), a bottom unless it's a dress, and
/// shoes. Returns nil when the closet can't fill the gaps.
enum LookRepair {
    static func repair(_ raw: [ClothingItem], keeping: [ClothingItem], closet: [ClothingItem],
                       occasion: Occasion, season: Season) -> (items: [ClothingItem], repaired: Bool)? {
        var bySlot: [BuilderSlot: ClothingItem] = [:]
        var repaired = false
        for item in keeping { bySlot[BuilderSlot.slot(for: item.category)] = item }
        for item in raw {
            let slot = BuilderSlot.slot(for: item.category)
            if let existing = bySlot[slot] {
                if existing.id != item.id { repaired = true }
                continue
            }
            bySlot[slot] = item
        }
        let dress = bySlot[.top]?.category == .dress
        if dress, bySlot[.bottom] != nil { bySlot[.bottom] = nil; repaired = true }

        var required: [BuilderSlot] = [.top, .shoes]
        if !dress { required.append(.bottom) }
        for slot in required where bySlot[slot] == nil {
            guard let filler = bestFiller(for: slot, closet: closet, occasion: occasion, season: season) else { return nil }
            bySlot[slot] = filler
            repaired = true
        }
        let order: [BuilderSlot] = [.outerwear, .top, .bottom, .shoes, .accessory]
        return (order.compactMap { bySlot[$0] }, repaired)
    }

    private static func bestFiller(for slot: BuilderSlot, closet: [ClothingItem], occasion: Occasion,
                                   season: Season) -> ClothingItem? {
        let candidates = closet.filter {
            slot == .top ? $0.category == .top : BuilderSlot.slot(for: $0.category) == slot
        }
        return candidates.max { score($0, occasion, season) < score($1, occasion, season) }
    }

    private static func score(_ item: ClothingItem, _ occasion: Occasion, _ season: Season) -> Int {
        var s = item.seasons.isEmpty || item.seasons.contains(season) ? 2 : 0
        if occasion == .work, item.formality == .business || item.formality == .smartCasual { s += 2 }
        if occasion != .work, item.formality == .casual || item.formality == .smartCasual { s += 1 }
        if item.favorite { s += 1 }
        return s
    }
}

// MARK: - On-device stylist

#if canImport(FoundationModels)
/// Apple's on-device model through the Foundation Models framework. It reads
/// each piece's details as text (it can't see photos), runs offline, and costs
/// nothing per request.
///
/// Answers are generated against a schema whose slots only accept pieces from
/// the closet, so the model can't name a piece you don't own or put two tops
/// in one look. Explanations come after the picks, so they describe them.
@available(macOS 26, *)
struct OnDeviceStylist: Stylist {
    /// The on-device model's window is 4,096 tokens on macOS 26 and 8,192 on
    /// macOS 27. About 40 described pieces (with what their photos look like)
    /// leaves room for the instructions, the schema and the answer.
    static let maxPieces = 40

    static let instructions = """
        You are a thoughtful personal stylist. You put outfits together only from the pieces in the \
        person's closet. You pay attention to color harmony, balancing textures, matching formality to \
        the occasion, and dressing for the season. A piece's "looks" note describes its photo, so trust \
        it for pattern, texture and vibe. Keep the language warm, concrete and brief, and only mention \
        pieces that are in the outfit.
        """

    private static let none = "none"

    func suggest(from closet: [ClothingItem], saved: [Outfit], taste: StylistTaste, occasion: Occasion, season: Season,
                 keeping: [ClothingItem], count: Int) async throws -> [StylistLook] {
        let pieces = Self.trim(closet, season: season, keeping: keeping)
        let labels = Labels(pieces, looks: await StylistVision.shared.descriptions(for: pieces))
        var prompt = """
            Closet:
            \(labels.text)

            Put together \(count) different outfit\(count == 1 ? "" : "s") for \(occasion.label.lowercased()) in \
            \(season.label.lowercased())\(taste.formalityLean.map { ", " + $0 } ?? ""). Each outfit should differ from the others by at least two pieces.
            """
        let savedLines = saved.prefix(8).map { outfit in
            outfit.itemIDs.compactMap { id in pieces.first { $0.id == id }.map(labels.label) }.joined(separator: " + ")
        }.filter { !$0.isEmpty }
        if !savedLines.isEmpty {
            prompt += "\nThese are already saved, so make something new: " + savedLines.joined(separator: "; ") + "."
        }
        let declinedLines = taste.looks.suffix(8).reversed().compactMap { look -> String? in
            let names = look.itemIDs.compactMap { id in pieces.first { $0.id == id }.map(labels.label) }
            return names.count < 2 ? nil : names.joined(separator: " + ") + " (\(look.reason.phrase))"
        }
        if !declinedLines.isEmpty {
            prompt += "\nThey turned these combinations down, so avoid them: " + declinedLines.joined(separator: "; ") + "."
        }
        if !taste.leanings.isEmpty {
            prompt += "\nFrom what they've turned down: " + taste.leanings.joined(separator: ", ") + "."
        }

        let lockedSlots = Dictionary(keeping.map { (BuilderSlot.slot(for: $0.category), $0) }, uniquingKeysWith: { a, _ in a })
        func slot(_ slot: BuilderSlot, _ description: String, optional: Bool) -> DynamicGenerationSchema.Property {
            let choices: [String]
            if let locked = lockedSlots[slot] {
                choices = [labels.label(locked)]
            } else {
                let fits = pieces.filter { BuilderSlot.slot(for: $0.category) == slot }.map(labels.label)
                choices = fits.isEmpty || optional || slot == .bottom ? fits + [Self.none] : fits
            }
            return .init(name: slot.rawValue, description: description,
                         schema: DynamicGenerationSchema(name: slot.rawValue.capitalized + "Choice", anyOf: choices))
        }
        let look = DynamicGenerationSchema(name: "Look", properties: [
            slot(.top, "The top or dress", optional: false),
            slot(.bottom, "The trousers, jeans, shorts or skirt; none only with a dress", optional: false),
            slot(.shoes, "The shoes", optional: false),
            slot(.outerwear, "A jacket or coat to layer on top, or none", optional: true),
            slot(.accessory, "An accessory, or none", optional: true),
            .init(name: "why", description: "One or two sentences on why these exact pieces work together, naming their colors, textures or cuts",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "name", description: "A short, evocative name for the outfit, two to four words, like Saturday market",
                  schema: DynamicGenerationSchema(type: String.self)),
        ])
        let root = DynamicGenerationSchema(name: "Looks", properties: [
            .init(name: "looks", schema: DynamicGenerationSchema(arrayOf: look, minimumElements: count, maximumElements: count)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: prompt, schema: schema,
                                                 options: GenerationOptions(maximumResponseTokens: 220 * count))
        let drafts = try response.content.value([GeneratedContent].self, forProperty: "looks")
        var looks: [StylistLook] = []
        for draft in drafts.prefix(count) {
            let raw = BuilderSlot.allCases.compactMap { slot -> ClothingItem? in
                (try? draft.value(String.self, forProperty: slot.rawValue)).flatMap(labels.item)
            }
            guard let fixed = LookRepair.repair(raw, keeping: keeping, closet: pieces,
                                                occasion: occasion, season: season),
                  !taste.declined(look: fixed.items.map(\.id)) else { continue }
            looks.append(StylistLook(name: (try? draft.value(String.self, forProperty: "name")) ?? "Stylist pick",
                                     itemIDs: fixed.items.map(\.id),
                                     why: (try? draft.value(String.self, forProperty: "why")) ?? "",
                                     wasRepaired: fixed.repaired))
        }
        return looks
    }

    func critique(outfit: [ClothingItem], occasion: Occasion, closet: [ClothingItem]) async throws -> String {
        let pieces = Self.trim(closet, season: .current(), keeping: outfit)
        let labels = Labels(pieces, looks: await StylistVision.shared.descriptions(for: pieces))
        let others = pieces.filter { p in !outfit.contains { $0.id == p.id } }
        guard !outfit.isEmpty else { return "" }
        let prompt = """
            Closet:
            \(labels.text)

            Today's outfit for \(occasion.label.lowercased()): \(outfit.map(labels.label).joined(separator: " + ")).
            Say what works about it, then pick one piece from the closet to swap in or add that would make it better.
            """
        let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Critique", properties: [
            .init(name: "works", description: "One sentence on what works about this outfit, mentioning only its pieces",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "swapIn", description: "The closet piece to swap in or add",
                  schema: DynamicGenerationSchema(name: "SwapIn", anyOf: others.isEmpty ? [Self.none] : others.map(labels.label))),
            .init(name: "reason", description: "Half a sentence on why that piece improves the outfit",
                  schema: DynamicGenerationSchema(type: String.self)),
        ]), dependencies: [])
        let session = LanguageModelSession(instructions: Self.instructions)
        let options = GenerationOptions(maximumResponseTokens: 200)
        let content: GeneratedContent
        if #available(macOS 27, *), StylistVision.isAvailable {
            // Show the model the outfit itself, not just the notes about it.
            var photos: [(String, URL)] = []
            for item in outfit {
                if let url = await StylistVision.shared.photoURL(for: item) { photos.append((labels.label(item), url)) }
            }
            content = try await session.respond(to: Prompt {
                prompt
                if !photos.isEmpty { "Photos of the outfit's pieces:" }
                photos.map { Attachment(imageURL: $0.1).label($0.0) }
            }, schema: schema, options: options).content
        } else {
            content = try await session.respond(to: prompt, schema: schema, options: options).content
        }
        let works = ((try? content.value(String.self, forProperty: "works")) ?? "").replacingOccurrences(of: "**", with: "")
        guard let swapIn = (try? content.value(String.self, forProperty: "swapIn")).flatMap(labels.item) else { return works }
        let reason = ((try? content.value(String.self, forProperty: "reason")) ?? "").replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let tail = reason.isEmpty ? "." : ": " + reason.prefix(1).lowercased() + reason.dropFirst() + "."
        let slot = BuilderSlot.slot(for: swapIn.category)
        if let replaced = outfit.first(where: { BuilderSlot.slot(for: $0.category) == slot }) {
            return works + " Try the \(swapIn.name.lowercased()) instead of the \(replaced.name.lowercased())" + tail
        }
        return works + " Add the \(swapIn.name.lowercased())" + tail
    }

    func gaps(in closet: [ClothingItem], outfits: [Outfit], taste: StylistTaste) async throws -> StylistGaps {
        var result = try await gapsFittingWindow(in: closet, taste: taste)
        // What you've turned down can rule out most of an answer; ask once
        // more and keep the new pieces.
        if result.pieces.count < 3, !taste.isEmpty, let more = try? await gapsFittingWindow(in: closet, taste: taste) {
            let names = Set(result.pieces.map { $0.name.lowercased() })
            result.pieces += more.pieces.filter { !names.contains($0.name.lowercased()) }.prefix(4 - result.pieces.count)
        }
        return result
    }

    private func gapsFittingWindow(in closet: [ClothingItem], taste: StylistTaste) async throws -> StylistGaps {
        do {
            return try await gaps(from: Self.trim(closet, season: .current(), keeping: []), taste: taste)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // A long answer can run past the window; ask again about fewer pieces.
            return try await gaps(from: Array(Self.trim(closet, season: .current(), keeping: []).prefix(max(6, closet.count * 2 / 3))),
                                  taste: taste)
        }
    }

    private func gaps(from pieces: [ClothingItem], taste: StylistTaste) async throws -> StylistGaps {
        let labels = Labels(pieces, looks: await StylistVision.shared.descriptions(for: pieces))
        let counts = Category.allCases.map { c in "\(pieces.filter { $0.category == c }.count) \(c.label.lowercased())" }
        func common(_ values: [String]) -> String {
            let tally = Dictionary(values.filter { !$0.isEmpty }.map { ($0, 1) }, uniquingKeysWith: +)
            return tally.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map(\.key).joined(separator: ", ")
        }
        var prompt = """
            Closet:
            \(labels.text)

            The closet has \(counts.joined(separator: ", ")).
            Most common colors: \(common(pieces.map { $0.displayColorName.lowercased() })).
            Most common fabrics: \(common(pieces.compactMap { $0.fabric == .unknown ? nil : $0.fabric.label.lowercased() })).
            Most common cuts: \(common(pieces.compactMap { $0.silhouette == .unknown ? nil : $0.silhouette.label.lowercased() })).
            Formality: \(common(pieces.map { $0.formality.label.lowercased() })).

            First describe this person's style in one specific sentence that names their colors and cuts. \
            Then suggest five different pieces they don't own yet that fit that style and would create the \
            most new outfits with what they have. Favor categories with few pieces, and don't suggest \
            anything close to a piece they already own.
            """
        if !taste.pieces.isEmpty {
            prompt += "\nThey turned these suggestions down, so don't suggest them or anything like them: "
                + taste.pieceLines().joined(separator: "; ") + "."
        }
        if !taste.leanings.isEmpty {
            prompt += "\nFrom what they've turned down: " + taste.leanings.joined(separator: ", ") + "."
        }
        let others = pieces.isEmpty ? [Self.none] : pieces.map(labels.label)
        let gap = DynamicGenerationSchema(name: "Gap", properties: [
            .init(name: "name", description: "The piece to look for, first, two to four words with color and fabric, like Navy wool blazer",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "category", description: "The kind of piece it is",
                  schema: DynamicGenerationSchema(name: "GapCategory", anyOf: Category.allCases.map(\.singular))),
            .init(name: "color", description: "The closest color to the one in its name",
                  schema: DynamicGenerationSchema(name: "GapColor", anyOf: ColorNamer.palette.map(\.0))),
            .init(name: "fabric", description: "The closest fabric to the one in its name",
                  schema: DynamicGenerationSchema(name: "GapFabric", anyOf: Fabric.allCases.filter { $0 != .unknown }.map(\.label))),
            .init(name: "pairsWith", description: "Two or three pieces they own that it goes with",
                  schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(name: "Owned", anyOf: others),
                                                  minimumElements: 2, maximumElements: 3)),
            .init(name: "why", description: "One sentence on how it fits their style and what it unlocks with those pieces",
                  schema: DynamicGenerationSchema(type: String.self)),
        ])
        let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Gaps", properties: [
            .init(name: "style", description: "One sentence describing their style",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "gaps", schema: DynamicGenerationSchema(arrayOf: gap, minimumElements: 5, maximumElements: 5)),
        ]), dependencies: [])

        let session = LanguageModelSession(instructions: Self.instructions)
        let content = try await session.respond(to: prompt, schema: schema,
                                                options: GenerationOptions(maximumResponseTokens: 750)).content
        let drafts = try content.value([GeneratedContent].self, forProperty: "gaps")
        let gaps = drafts.compactMap { draft -> StylistGap? in
            guard let name = try? draft.value(String.self, forProperty: "name"), !name.isEmpty else { return nil }
            let categoryLabel = try? draft.value(String.self, forProperty: "category")
            let colorName = try? draft.value(String.self, forProperty: "color")
            let fabricLabel = try? draft.value(String.self, forProperty: "fabric")
            let owned = ((try? draft.value([String].self, forProperty: "pairsWith")) ?? []).compactMap(labels.item)
            let category = Category.allCases.first { $0.singular == categoryLabel } ?? .top
            let colorHex = ColorNamer.palette.first { $0.0 == colorName }?.1 ?? "#B8A88A"
            let fabric = Fabric.allCases.first { $0.label == fabricLabel } ?? .unknown
            if taste.rules(out: name, category: category, colorName: colorName ?? "", fabric: fabric) { return nil }
            // Skip near-copies of something already owned (navy denim jeans
            // when there are indigo denim jeans).
            let slot = BuilderSlot.slot(for: category)
            let family = ColorFamily.of(hex: colorHex)
            if pieces.contains(where: { BuilderSlot.slot(for: $0.category) == slot && $0.colorFamily == family
                && ($0.fabric == fabric || $0.fabric == .unknown) }) { return nil }
            // It's worn with pieces from other slots, not instead of them.
            var seen = Set<UUID>()
            let pairs = owned.filter { BuilderSlot.slot(for: $0.category) != slot }.map(\.id)
                .filter { seen.insert($0).inserted }
            return StylistGap(name: name.replacingOccurrences(of: "**", with: ""), category: category,
                              colorHex: colorHex, fabric: fabric,
                              why: ((try? draft.value(String.self, forProperty: "why")) ?? "").replacingOccurrences(of: "**", with: ""),
                              pairsWith: pairs)
        }
        // Different kinds of pieces first, at most four.
        var kinds = Set<String>()
        let varied = gaps.filter { kinds.insert($0.name.lowercased()).inserted }
        let picked = Array((varied.filter { g in varied.first { $0.category == g.category } == g }
            + varied.filter { g in varied.first { $0.category == g.category } != g }).prefix(4))
        let style = ((try? content.value(String.self, forProperty: "style")) ?? "").replacingOccurrences(of: "**", with: "")
        return StylistGaps(style: style, pieces: picked)
    }

    /// Keeps the prompt inside the model's window: locked pieces first, then
    /// in-season favorites and the most worn.
    static func trim(_ closet: [ClothingItem], season: Season, keeping: [ClothingItem]) -> [ClothingItem] {
        guard closet.count > maxPieces else { return closet }
        let keep = Set(keeping.map(\.id))
        let ranked = closet.sorted { a, b in
            func rank(_ i: ClothingItem) -> Int {
                (keep.contains(i.id) ? 100 : 0) + (i.seasons.isEmpty || i.seasons.contains(season) ? 10 : 0)
                    + (i.favorite ? 5 : 0)
            }
            return (rank(a), a.timesWorn) > (rank(b), b.timesWorn)
        }
        return Array(ranked.prefix(maxPieces))
    }

    /// A unique, readable label per piece ("Merino crewneck, olive"), used both
    /// in the closet list and as the allowed answers for each slot.
    private struct Labels {
        private var byLabel: [String: ClothingItem] = [:]
        private var byID: [UUID: String] = [:]
        let text: String

        init(_ pieces: [ClothingItem], looks: [UUID: String] = [:]) {
            var lines: [String] = []
            for piece in pieces {
                var label = "\(piece.name.trimmingCharacters(in: .whitespaces)), \(piece.displayColorName.lowercased())"
                    .replacingOccurrences(of: "  ", with: " ")
                var n = 2
                while byLabel[label] != nil { label = "\(label) \(n)"; n += 1 }
                byLabel[label] = piece
                byID[piece.id] = label
                var line = "- " + label + ": " + StylistCatalog.details(for: piece)
                if let look = looks[piece.id] { line += " | looks: " + look }
                lines.append(line)
            }
            text = lines.joined(separator: "\n")
        }

        func label(_ item: ClothingItem) -> String { byID[item.id] ?? item.name }
        func item(_ label: String) -> ClothingItem? { byLabel[label] }
    }
}
#endif
