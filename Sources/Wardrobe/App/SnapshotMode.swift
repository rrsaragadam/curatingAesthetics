import AppKit
import SwiftUI

/// Debug-only snapshot run. With `WARDROBE_SNAPSHOT=<folder>` set, the app uses a
/// throwaway library (`WARDROBE_STORE`, default /tmp/Wardrobe-snapshot-store),
/// walks every screen in light and dark mode, saves one PNG per screen and
/// mode with `screencapture -l`, and quits. It never touches the real library.
@MainActor
enum SnapshotMode {
    static let outputURL: URL? = ProcessInfo.processInfo.environment["WARDROBE_SNAPSHOT"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    static var isActive: Bool { outputURL != nil }

    /// A fresh, empty library for the run, or nil to use the real one.
    static let storeURL: URL? = {
        guard isActive else { return nil }
        let path = ProcessInfo.processInfo.environment["WARDROBE_STORE"] ?? "/tmp/Wardrobe-snapshot-store"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        // `WARDROBE_STORE_FROM=<library folder>` starts from a copy of a real
        // library instead of an empty one. The original is never touched.
        if let from = ProcessInfo.processInfo.environment["WARDROBE_STORE_FROM"] {
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: from, isDirectory: true), to: url)
        }
        return url
    }()

    private struct Shot {
        let name: String
        var wait: Double = 1.2
        let setUp: @MainActor (WardrobeStore, AppNavigation) -> Void
    }

    /// `WARDROBE_SNAPSHOT_LINK=<product url>` adds a shot of that page imported
    /// in the link sheet. It needs the network, so it waits longer.
    private static var linkShots: [Shot] {
        guard let link = ProcessInfo.processInfo.environment["WARDROBE_SNAPSHOT_LINK"] else { return [] }
        return [Shot(name: "add-from-link-preview", wait: 25) { _, nav in
            // Close the sheet from the previous shot first, so it reopens fresh.
            nav.showAddFromLink = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                nav.linkToAdd = link
                nav.showAddFromLink = true
            }
        }]
    }

    private static var shots: [Shot] { baseShots + linkShots }

    private static let baseShots: [Shot] = [
        Shot(name: "closet-empty") { _, nav in nav.section = .closet },
        Shot(name: "closet") { store, nav in
            store.loadSampleCloset()
            nav.section = .closet
            nav.collection = .all
        },
        Shot(name: "closet-detail") { store, nav in nav.selectedItemID = store.items.first?.id },
        Shot(name: "closet-detail-last") { store, nav in nav.selectedItemID = store.items.last?.id },
        Shot(name: "closet-detail-shoes") { store, nav in
            nav.selectedItemID = store.items.first { $0.category == .shoes }?.id
        },
        Shot(name: "favorites") { _, nav in nav.selectedItemID = nil; nav.collection = .favorites },
        Shot(name: "in-season") { _, nav in nav.collection = .inSeason },
        Shot(name: "rarely-worn") { _, nav in nav.collection = .rarelyWorn },
        Shot(name: "builder") { _, nav in nav.collection = .all; nav.section = .builder },
        Shot(name: "builder-styled") { store, nav in nav.style(store.items[0]) },
        Shot(name: "lookbook") { _, nav in nav.section = .lookbook },
        Shot(name: "add-from-link") { _, nav in nav.section = .closet; nav.showAddFromLink = true },
    ]

    static func run(store: WardrobeStore, nav: AppNavigation) {
        guard let outputURL else { return }
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            for shot in shots {
                shot.setUp(store, nav)
                for (index, mode) in ["light", "dark"].enumerated() {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(index == 0 ? shot.wait : 1.2))
                    capture(outputURL.appendingPathComponent("\(shot.name)-\(mode).png"))
                }
            }
            nav.showAddFromLink = false
            try? await Task.sleep(for: .seconds(0.5))
            log("SNAPSHOT done \(outputURL.path)")
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Wardrobe" })
                ?? NSApp.windows.first(where: \.isVisible) else {
            log("SNAPSHOT no window for \(url.lastPathComponent)")
            return
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try? task.run()
        task.waitUntilExit()
        log("SNAPSHOT \(url.path)")
        if let sheet = window.attachedSheet {
            let sheetURL = url.deletingPathExtension().appendingPathExtension("sheet.png")
            let sheetTask = Process()
            sheetTask.executableURL = task.executableURL
            sheetTask.arguments = ["-x", "-o", "-l", "\(sheet.windowNumber)", sheetURL.path]
            try? sheetTask.run()
            sheetTask.waitUntilExit()
            log("SNAPSHOT \(sheetURL.path)")
        }
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
