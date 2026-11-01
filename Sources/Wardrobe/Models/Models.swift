import Foundation

// MARK: - Category

/// The slot a piece fills in an outfit.
enum Category: String, Codable, CaseIterable, Identifiable {
    case top
    case bottom
    case dress
    case outerwear
    case shoes
    case accessory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Tops"
        case .bottom: return "Bottoms"
        case .dress: return "Dresses"
        case .outerwear: return "Outerwear"
        case .shoes: return "Shoes"
        case .accessory: return "Accessories"
        }
    }

    var singular: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .dress: return "Dress"
        case .outerwear: return "Outerwear"
        case .shoes: return "Shoes"
        case .accessory: return "Accessory"
        }
    }

    var symbol: String {
        switch self {
        case .top: return "tshirt"
        case .bottom: return "rectangle.split.2x1"
        case .dress: return "figure.stand.dress"
        case .outerwear: return "wind"
        case .shoes: return "shoe"
        case .accessory: return "bag"
        }
    }
}

// MARK: - Season / formality

enum Season: String, Codable, CaseIterable, Identifiable, Comparable {
    case spring, summer, fall, winter
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    static func < (lhs: Season, rhs: Season) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// Northern-hemisphere season for a date.
    static func current(_ date: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
        }
    }

    static func describe(_ seasons: Set<Season>) -> String {
        if seasons.isEmpty || seasons.count == allCases.count { return "All year" }
        let sorted = seasons.sorted()
        let words = sorted.map { $0.rawValue }
        return words.joined(separator: ", ").capitalizedFirst
    }
}

enum Formality: String, Codable, CaseIterable, Identifiable {
    case casual, smartCasual, business, formal, athletic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .casual: return "Casual"
        case .smartCasual: return "Smart casual"
        case .business: return "Business"
        case .formal: return "Formal"
        case .athletic: return "Athletic"
        }
    }
}

// MARK: - Clothing item

struct ClothingItem: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: Category
    /// Main color as "#RRGGBB".
    var colorHex: String = "#B8A88A"
    var colorName: String = ""
    var brand: String = ""
    var seasons: Set<Season> = []
    var formality: Formality = .casual
    var fabric: Fabric = .unknown
    var silhouette: Silhouette = .unknown
    /// Free text from the tag or product page, e.g. "100% merino wool".
    var material: String = ""
    var size: String = ""
    var care: String = ""
    var tags: [String] = []
    var notes: String = ""
    var favorite: Bool = false
    /// File name (inside the store's image folder) of the cut-out PNG. Nil means
    /// the piece is drawn as an illustration in its color and texture.
    var imageFile: String?
    /// Product page the piece came from, if it was added from a link.
    var sourceURL: String?
    var addedAt: Date = .now
    var timesWorn: Int = 0
    var lastWornAt: Date?

    var colorFamily: ColorFamily { ColorFamily.of(hex: colorHex) }

    var displayColorName: String {
        colorName.isEmpty ? ColorNamer.name(forHex: colorHex) : colorName
    }

    /// True when the piece hasn't been worn for a long time (or ever, after a while).
    func isIdle(now: Date = .now) -> Bool {
        let reference = lastWornAt ?? addedAt
        return now.timeIntervalSince(reference) > 60 * 24 * 3600
    }

    var sourceHost: String? {
        guard let s = sourceURL, let host = URL(string: s)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let haystack = ([name, brand, displayColorName, colorFamily.label, category.label, category.singular,
                         fabric.label, silhouette == .unknown ? "" : silhouette.label, material, size, notes] + tags).joined(separator: " ").lowercased()
        return q.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

extension ClothingItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, category, colorHex, colorName, brand, seasons, formality, fabric, silhouette, material, size, care
        case tags, notes, favorite, imageFile, sourceURL, addedAt, timesWorn, lastWornAt
    }

    // Every field except id/name/category is optional on disk, so older files keep
    // loading as the model grows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = (try? c.decode(Category.self, forKey: .category)) ?? .top
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#B8A88A"
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        seasons = try c.decodeIfPresent(Set<Season>.self, forKey: .seasons) ?? []
        formality = (try? c.decodeIfPresent(Formality.self, forKey: .formality)) ?? .casual
        fabric = (try? c.decodeIfPresent(Fabric.self, forKey: .fabric)) ?? .unknown
        silhouette = (try? c.decodeIfPresent(Silhouette.self, forKey: .silhouette)) ?? .unknown
        material = try c.decodeIfPresent(String.self, forKey: .material) ?? ""
        size = try c.decodeIfPresent(String.self, forKey: .size) ?? ""
        care = try c.decodeIfPresent(String.self, forKey: .care) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .now
        timesWorn = try c.decodeIfPresent(Int.self, forKey: .timesWorn) ?? 0
        lastWornAt = try c.decodeIfPresent(Date.self, forKey: .lastWornAt)
    }
}

// MARK: - Outfit

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case everyday, work, dateNight, weekend, travel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .everyday: return "Everyday"
        case .work: return "Work"
        case .dateNight: return "Date night"
        case .weekend: return "Weekend"
        case .travel: return "Travel"
        }
    }
}

struct Outfit: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var itemIDs: [UUID]
    var occasion: Occasion = .everyday
    var createdAt: Date = .now
    /// Your own 1–5 stars; 0 means unrated.
    var rating: Int = 0
    /// Every day this outfit was worn, newest last.
    var wornDates: [Date] = []
    var notes: String = ""

    var timesWorn: Int { wornDates.count }
    var lastWorn: Date? { wornDates.max() }

    func wasWorn(on day: Date, calendar: Calendar = .current) -> Bool {
        wornDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }
}

extension Outfit: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, itemIDs, occasion, createdAt, rating, wornDates, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled look"
        itemIDs = try c.decodeIfPresent([UUID].self, forKey: .itemIDs) ?? []
        occasion = (try? c.decodeIfPresent(Occasion.self, forKey: .occasion)) ?? .everyday
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        wornDates = try c.decodeIfPresent([Date].self, forKey: .wornDates) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

// MARK: - File

/// Everything persisted to disk.
struct WardrobeData: Codable {
    var version: Int = 1
    var items: [ClothingItem] = []
    var outfits: [Outfit] = []

    init(items: [ClothingItem] = [], outfits: [Outfit] = []) {
        self.items = items
        self.outfits = outfits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decodeIfPresent([ClothingItem].self, forKey: .items) ?? []
        outfits = try c.decodeIfPresent([Outfit].self, forKey: .outfits) ?? []
    }
}

// MARK: - Helpers

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
