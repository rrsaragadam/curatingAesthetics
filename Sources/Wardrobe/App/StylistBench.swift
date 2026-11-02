import AppKit
import Foundation

/// Debug-only stylist check. With `WARDROBE_STYLIST_BENCH=<file.md>` set, the
/// app asks the stylist for looks, critiques and gaps on the sample closet and
/// on a read-only copy of the real library, times every call, writes a report
/// and quits. Nothing is saved to either library; photo descriptions are
/// cached next to the report, so delete that file to time them from scratch.
/// `WARDROBE_STYLIST_BENCH_LIBRARY_ONLY=1` skips the sample closet.
@MainActor
enum StylistBench {
    static let outputURL: URL? = ProcessInfo.processInfo.environment["WARDROBE_STYLIST_BENCH"]
        .map { URL(fileURLWithPath: $0) }

    static var isActive: Bool { outputURL != nil }

    static func run() {
        guard let outputURL else { return }
        Task { @MainActor in
            var report = "# On-device stylist check\n\n"
            guard let stylist = StylistProvider.current else {
                report += "Stylist unavailable: \(StylistProvider.unavailableReason ?? "unknown")\n"
                finish(report, to: outputURL)
                return
            }
            if ProcessInfo.processInfo.environment["WARDROBE_STYLIST_BENCH_LIBRARY_ONLY"] == nil {
                let sample = SampleCloset.make()
                report += await bench(stylist, title: "Sample closet", closet: sample.items, saved: sample.outfits)
            }
            if let real = realLibrary(), !real.items.isEmpty {
                report += await describePhotos(real.items)
                report += await bench(stylist, title: "Your library", closet: real.items, saved: real.outfits)
            }
            finish(report, to: outputURL)
        }
    }

    private static func bench(_ stylist: Stylist, title: String, closet: [ClothingItem], saved: [Outfit]) async -> String {
        let season = Season.current()
        var out = "## \(title) (\(closet.count) pieces, \(season.label.lowercased()))\n\n"
        var timings: [Double] = []
        var looksTotal = 0, repaired = 0, failures = 0

        func timed<T>(_ body: () async throws -> T) async -> (T?, Double, String?) {
            let start = Date()
            do {
                let value = try await body()
                return (value, Date().timeIntervalSince(start), nil)
            } catch {
                return (nil, Date().timeIntervalSince(start), String(describing: error))
            }
        }
        func names(_ ids: [UUID]) -> String {
            ids.compactMap { id in closet.first { $0.id == id } }
                .map { "\($0.name) (\($0.displayColorName.lowercased()))" }
                .joined(separator: " + ")
        }

        out += "### Looks\n\n"
        for occasion in Occasion.allCases {
            let (looks, seconds, error) = await timed {
                try await stylist.suggest(from: closet, saved: saved, occasion: occasion, season: season,
                                          keeping: [], count: 3)
            }
            timings.append(seconds)
            out += "**\(occasion.label)**, 3 looks in \(String(format: "%.1f", seconds))s\n\n"
            if let error { failures += 1; out += "- Failed: \(error)\n\n"; continue }
            for look in looks ?? [] {
                looksTotal += 1
                if look.wasRepaired { repaired += 1 }
                out += "- *\(look.name)*\(look.wasRepaired ? " (repaired)" : ""): \(names(look.itemIDs)). \(look.why)\n"
            }
            out += "\n"
        }

        // One builder-style request: a single look around a locked piece.
        if let anchor = closet.first(where: { $0.category == .jacket || $0.category == .outerwear }) ?? closet.first {
            let (looks, seconds, error) = await timed {
                try await stylist.suggest(from: closet, saved: saved, occasion: .weekend, season: season,
                                          keeping: [anchor], count: 1)
            }
            timings.append(seconds)
            out += "**Builder: one weekend look around the \(anchor.name)**, \(String(format: "%.1f", seconds))s\n\n"
            if let error { failures += 1; out += "- Failed: \(error)\n\n" }
            for look in looks ?? [] {
                looksTotal += 1
                if look.wasRepaired { repaired += 1 }
                out += "- *\(look.name)*\(look.wasRepaired ? " (repaired)" : ""): \(names(look.itemIDs)). \(look.why)\n"
            }
            out += "\n"
        }

        out += "### Critiques\n\n"
        let critiqueTargets: [(String, [ClothingItem], Occasion)] = saved.isEmpty
            ? [("A random look", randomLook(from: closet), .everyday)]
            : saved.prefix(3).map { o in (o.name, o.itemIDs.compactMap { id in closet.first { $0.id == id } }, o.occasion) }
        for (name, items, occasion) in critiqueTargets where !items.isEmpty {
            let (text, seconds, error) = await timed {
                try await stylist.critique(outfit: items, occasion: occasion, closet: closet)
            }
            timings.append(seconds)
            if error != nil { failures += 1 }
            out += "**\(name)** (\(names(items.map(\.id)))), \(String(format: "%.1f", seconds))s\n\n> \(text ?? "Failed: \(error ?? "")")\n\n"
        }

        out += "### Gaps\n\n"
        let (gaps, gapSeconds, gapError) = await timed { try await stylist.gaps(in: closet, outfits: saved) }
        timings.append(gapSeconds)
        if gapError != nil { failures += 1 }
        out += "\(String(format: "%.1f", gapSeconds))s\n\n"
        if let gaps {
            out += "Style: \(gaps.style)\n\n"
            for gap in gaps.pieces {
                out += "- *\(gap.name)* (\(gap.category.singular.lowercased()), \(ColorNamer.name(forHex: gap.colorHex).lowercased()) "
                    + "\(gap.fabric.label.lowercased())), with \(names(gap.pairsWith)). \(gap.why)\n"
            }
            out += "\n"
        } else {
            out += "- Failed: \(gapError ?? "")\n\n"
        }

        let sorted = timings.sorted()
        out += "### Summary\n\n"
        out += "- Calls: \(timings.count), failed: \(failures)\n"
        out += "- Time per call: median \(String(format: "%.1f", sorted[sorted.count / 2]))s, "
            + "fastest \(String(format: "%.1f", sorted.first ?? 0))s, slowest \(String(format: "%.1f", sorted.last ?? 0))s\n"
        out += "- Looks: \(looksTotal), repaired by the app: \(repaired)\n\n"
        return out
    }

    /// Times describing every photo in the library, and lists what the model saw.
    private static func describePhotos(_ items: [ClothingItem]) async -> String {
        guard StylistVision.isAvailable else { return "Photos: this Mac's model can't read images, so the stylist uses text only.\n\n" }
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wardrobe", isDirectory: true)
        await StylistVision.shared.configure(imagesURL: library.appendingPathComponent("Images", isDirectory: true),
                                             cacheURL: outputURL!.deletingLastPathComponent().appendingPathComponent("stylist-photos.json"))
        let start = Date()
        let looks = await StylistVision.shared.descriptions(for: items)
        var out = "## Photos (\(looks.count) described in \(String(format: "%.1f", Date().timeIntervalSince(start)))s)\n\n"
        for item in items { if let look = looks[item.id] { out += "- \(item.name): \(look)\n" } }
        return out + "\n"
    }

    private static func randomLook(from closet: [ClothingItem]) -> [ClothingItem] {
        [Category.top, .bottom, .shoes].compactMap { c in closet.filter { $0.category == c }.randomElement() }
    }

    /// The real library, decoded straight from disk so nothing can write to it.
    private static func realLibrary() -> WardrobeData? {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wardrobe/wardrobe.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WardrobeData.self, from: data)
    }

    private static func finish(_ report: String, to url: URL) {
        try? report.write(to: url, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("STYLIST BENCH done \(url.path)\n".utf8))
        NSApp.terminate(nil)
    }
}
