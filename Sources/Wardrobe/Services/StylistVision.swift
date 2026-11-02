import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What each piece's photo looks like, in a few words, so the stylist can
/// weigh pattern, texture and vibe that the typed details miss.
///
/// The on-device model reads photos from macOS 27. Each photo is described
/// once and saved next to the library (keyed by the photo's file name, so a
/// new photo gets a fresh description); every stylist request then reuses
/// the text, which is far cheaper than sending all the photos each time.
actor StylistVision {
    static let shared = StylistVision()

    private var imagesURL: URL?
    private var cacheURL: URL?
    private var cache: [String: String] = [:]

    func configure(imagesURL: URL, cacheURL: URL) {
        self.imagesURL = imagesURL
        self.cacheURL = cacheURL
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = saved
        }
    }

    /// True when this Mac's model can read photos.
    nonisolated static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27, *) {
            return SystemLanguageModel.default.isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif
        return false
    }

    /// The photo file for a piece, if it has one.
    func photoURL(for item: ClothingItem) -> URL? {
        guard let file = item.imageFile, let imagesURL else { return nil }
        let url = imagesURL.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Descriptions for the pieces that have photos, describing any that
    /// haven't been seen yet.
    func descriptions(for items: [ClothingItem]) async -> [UUID: String] {
        guard Self.isAvailable else { return [:] }
        var result: [UUID: String] = [:]
        for item in items {
            if let text = await description(for: item) { result[item.id] = text }
        }
        return result
    }

    /// Describes every piece ahead of time, so the first stylist request
    /// doesn't wait on it.
    func warm(_ items: [ClothingItem]) async {
        _ = await descriptions(for: items)
    }

    private func description(for item: ClothingItem) async -> String? {
        guard let file = item.imageFile else { return nil }
        if let cached = cache[file] { return cached }
        guard let url = photoURL(for: item) else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 27, *) {
            let session = LanguageModelSession()
            let prompt = Prompt {
                """
                Describe this \(item.category.singular.lowercased()) for a stylist in at most twenty words: its \
                exact color and any pattern, how the fabric looks, the cut and fit, and its style (for example \
                minimalist, workwear, streetwear, preppy, sporty). No full sentences.
                """
                Attachment(imageURL: url)
            }
            guard let text = try? await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 60))
                .content.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
                .replacingOccurrences(of: "\n", with: " ")
            else { return nil }
            cache[file] = text
            save()
            return text
        }
        #endif
        return nil
    }

    private func save() {
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
