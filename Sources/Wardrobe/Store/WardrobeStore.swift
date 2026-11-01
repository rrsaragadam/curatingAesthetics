import AppKit
import Foundation
import Observation

/// Owns all wardrobe data. Saves to
/// ~/Library/Application Support/Wardrobe/wardrobe.json and keeps cut-out
/// images as PNGs in ~/Library/Application Support/Wardrobe/Images.
@MainActor
@Observable
final class WardrobeStore {
    private(set) var items: [ClothingItem] = []
    private(set) var outfits: [Outfit] = []
    var lastError: String?

    let rootURL: URL
    let imagesURL: URL
    private var dataURL: URL { rootURL.appendingPathComponent("wardrobe.json") }
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]

    init(rootURL: URL? = nil) {
        let fm = FileManager.default
        let base = rootURL ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wardrobe", isDirectory: true)
        self.rootURL = base
        self.imagesURL = base.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode(WardrobeData.self, from: data)
            items = decoded.items
            outfits = decoded.outfits
        } catch {
            // Keep a copy so a bad file is never silently overwritten.
            let backup = rootURL.appendingPathComponent("wardrobe-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: dataURL, to: backup)
            lastError = "Couldn't read your wardrobe file, so a copy was saved as \(backup.lastPathComponent)."
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(WardrobeData(items: items, outfits: outfits))
            try data.write(to: dataURL, options: .atomic)
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: Images

    func image(for item: ClothingItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        if let cached = imageCache[file] { return cached }
        let url = imagesURL.appendingPathComponent(file)
        guard let img = NSImage(contentsOf: url) else { return nil }
        imageCache[file] = img
        return img
    }

    private func storeImage(_ png: Data) throws -> String {
        let fileName = UUID().uuidString + ".png"
        try png.write(to: imagesURL.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    /// Imports a photo from disk: removes the background (when asked), trims and
    /// downsizes it, guesses its color and category, and adds a new item.
    @discardableResult
    func importPhoto(at url: URL, removeBackground: Bool) async -> ClothingItem? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let processed = try await ImageProcessor.process(imageData: data, removeBackground: removeBackground)
            let baseName = url.deletingPathExtension().lastPathComponent
            let category = processed.categoryGuess ?? .top
            var item = ClothingItem(
                name: Self.prettyName(from: baseName, category: category),
                category: category,
                imageFile: try storeImage(processed.png)
            )
            if let rgb = processed.dominantColor {
                item.colorHex = rgb.hex
                item.colorName = ColorNamer.name(for: rgb)
            }
            if let fabric = Fabric.guess(from: baseName) { item.fabric = fabric }
            items.append(item)
            save()
            return item
        } catch {
            lastError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    /// Adds a piece pulled from a product page. The photo has already been
    /// processed by `ProductImporter`.
    @discardableResult
    func addImported(_ draft: ClothingItem, png: Data?) -> ClothingItem {
        var item = draft
        if let png, let file = try? storeImage(png) { item.imageFile = file }
        items.append(item)
        save()
        return item
    }

    /// Replaces a piece's photo with a new one (for example a better shot).
    func replacePhoto(of item: ClothingItem, with url: URL, removeBackground: Bool) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let processed = try await ImageProcessor.process(imageData: data, removeBackground: removeBackground)
            var updated = item
            let old = item.imageFile
            updated.imageFile = try storeImage(processed.png)
            update(updated)
            if let old {
                try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(old))
                imageCache[old] = nil
            }
        } catch {
            lastError = "Couldn't use that photo: \(error.localizedDescription)"
        }
    }

    private static func prettyName(from fileName: String, category: Category) -> String {
        // Camera file names like IMG_1234 aren't useful as names.
        let lowered = fileName.lowercased()
        let cameraPrefixes = ["img", "dsc", "screenshot", "screen shot", "photo", "pxl", "image"]
        if cameraPrefixes.contains(where: { lowered.hasPrefix($0) }) || fileName.count > 40
            || fileName.allSatisfy({ $0.isNumber || $0 == "_" || $0 == "-" }) {
            return "New \(category.singular.lowercased())"
        }
        return fileName.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalizedFirst
    }

    // MARK: Items

    func item(id: UUID) -> ClothingItem? { items.first { $0.id == id } }

    func items(in category: Category) -> [ClothingItem] {
        items.filter { $0.category == category }
    }

    func update(_ item: ClothingItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }

    func toggleFavorite(_ item: ClothingItem) {
        var copy = item
        copy.favorite.toggle()
        update(copy)
    }

    func delete(_ item: ClothingItem) {
        items.removeAll { $0.id == item.id }
        if let file = item.imageFile {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(file))
            imageCache[file] = nil
        }
        // Drop the piece from saved outfits; remove outfits left empty.
        for i in outfits.indices {
            outfits[i].itemIDs.removeAll { $0 == item.id }
        }
        outfits.removeAll { $0.itemIDs.isEmpty }
        save()
    }

    // MARK: Collections

    func items(in collection: ClosetCollection) -> [ClothingItem] {
        switch collection {
        case .all: return items
        case .favorites: return items.filter(\.favorite)
        case .inSeason:
            let now = Season.current()
            return items.filter { $0.seasons.isEmpty || $0.seasons.contains(now) }
        case .rarelyWorn: return items.filter { $0.isIdle() }
        }
    }

    // MARK: Outfits

    func items(of outfit: Outfit) -> [ClothingItem] {
        outfit.itemIDs.compactMap { item(id: $0) }
    }

    func outfits(containing item: ClothingItem) -> [Outfit] {
        outfits.filter { $0.itemIDs.contains(item.id) }
    }

    /// A saved outfit made of exactly these pieces, if any.
    func outfit(matching ids: Set<UUID>) -> Outfit? {
        guard !ids.isEmpty else { return nil }
        return outfits.first { Set($0.itemIDs) == ids }
    }

    @discardableResult
    func saveOutfit(name: String, itemIDs: [UUID], occasion: Occasion) -> Outfit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let outfit = Outfit(name: trimmed.isEmpty ? "Look \(outfits.count + 1)" : trimmed,
                            itemIDs: itemIDs, occasion: occasion)
        outfits.insert(outfit, at: 0)
        save()
        return outfit
    }

    func update(_ outfit: Outfit) {
        guard let idx = outfits.firstIndex(where: { $0.id == outfit.id }) else { return }
        outfits[idx] = outfit
        save()
    }

    func delete(_ outfit: Outfit) {
        outfits.removeAll { $0.id == outfit.id }
        save()
    }

    /// Logs an outfit as worn on a day (today by default) and bumps every piece's
    /// wear count. Logging the same day twice does nothing.
    func markWorn(_ outfit: Outfit, on day: Date = .now) {
        guard let idx = outfits.firstIndex(where: { $0.id == outfit.id }),
              !outfits[idx].wasWorn(on: day) else { return }
        outfits[idx].wornDates.append(day)
        for id in outfit.itemIDs {
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].timesWorn += 1
                if (items[i].lastWornAt ?? .distantPast) < day { items[i].lastWornAt = day }
            }
        }
        save()
    }

    /// Undoes `markWorn` for a day.
    func unmarkWorn(_ outfit: Outfit, on day: Date = .now) {
        guard let idx = outfits.firstIndex(where: { $0.id == outfit.id }) else { return }
        let before = outfits[idx].wornDates.count
        outfits[idx].wornDates.removeAll { Calendar.current.isDate($0, inSameDayAs: day) }
        guard outfits[idx].wornDates.count < before else { return }
        for id in outfit.itemIDs {
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].timesWorn = max(0, items[i].timesWorn - 1)
                items[i].lastWornAt = outfits.filter { $0.itemIDs.contains(id) }
                    .flatMap(\.wornDates).max()
            }
        }
        save()
    }

    /// The outfit logged for each day of the week containing `date`, Monday first.
    func week(containing date: Date = .now) -> [(day: Date, outfit: Outfit?)] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { offset -> (day: Date, outfit: Outfit?)? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let worn = outfits.first { $0.wasWorn(on: day, calendar: cal) }
            return (day, worn)
        }
    }

    // MARK: Sample closet

    var isEmpty: Bool { items.isEmpty && outfits.isEmpty }

    /// Fills an empty closet with illustrated sample pieces and looks, so the app
    /// can be explored before any photos are added.
    func loadSampleCloset() {
        guard isEmpty else { return }
        let sample = SampleCloset.make()
        items = sample.items
        outfits = sample.outfits
        save()
    }

    /// Removes the sample pieces (those without a photo or link) and their outfits.
    func clearSampleCloset() {
        let sampleIDs = Set(items.filter { $0.tags.contains(SampleCloset.tag) }.map(\.id))
        items.removeAll { sampleIDs.contains($0.id) }
        outfits.removeAll { !Set($0.itemIDs).isDisjoint(with: sampleIDs) }
        save()
    }

    var hasSamplePieces: Bool { items.contains { $0.tags.contains(SampleCloset.tag) } }
}

/// Smart lists in the sidebar.
enum ClosetCollection: String, CaseIterable, Identifiable, Hashable {
    case all, favorites, inSeason, rarelyWorn
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Everything"
        case .favorites: return "Favorites"
        case .inSeason: return "\(Season.current().label) rotation"
        case .rarelyWorn: return "Rarely worn"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart"
        case .inSeason: return "leaf"
        case .rarelyWorn: return "moon.zzz"
        }
    }
}
