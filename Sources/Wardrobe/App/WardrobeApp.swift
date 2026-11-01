import AppKit
import SwiftUI

@main
struct WardrobeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WardrobeStore(rootURL: SnapshotMode.storeURL)
    @State private var nav = AppNavigation()

    init() {
        Typeface.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("Wardrobe", id: "main") {
            RootView()
                .environment(store)
                .environment(nav)
                .frame(minWidth: 1080, minHeight: 680)
                .tint(Theme.green)
                .task { SnapshotMode.run(store: store, nav: nav) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1340, height: 860)
        .commands { WardrobeCommands(nav: nav) }

        Settings {
            SettingsView()
                .environment(store)
                .tint(Theme.green)
        }
    }
}

/// Running from a Swift package (rather than an .app bundle) starts the process
/// as a background tool; this makes it a regular app with a Dock icon and focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum AppSection: String, CaseIterable, Identifiable {
    case closet, builder, lookbook
    var id: String { rawValue }

    var label: String {
        switch self {
        case .closet: return "Closet"
        case .builder: return "Outfit builder"
        case .lookbook: return "Lookbook"
        }
    }

    var symbol: String {
        switch self {
        case .closet: return "hanger"
        case .builder: return "square.stack.3d.up"
        case .lookbook: return "book.closed"
        }
    }
}

/// Where the window is and what it's showing. Shared so any screen can, say,
/// jump to the builder with a piece already in place.
@MainActor
@Observable
final class AppNavigation {
    var section: AppSection = .closet
    var collection: ClosetCollection = .all
    var selectedItemID: UUID?
    var showPhotoImporter = false
    var showAddFromLink = false
    /// A product link for the link sheet to fetch as soon as it opens.
    var linkToAdd: String?
    /// Set by "Style this piece"; the builder places it and clears this.
    var pieceToStyle: UUID?
    /// Set from the lookbook to reopen an outfit in the builder.
    var outfitToEdit: UUID?

    func style(_ item: ClothingItem) {
        pieceToStyle = item.id
        section = .builder
    }

    func open(_ outfit: Outfit) {
        outfitToEdit = outfit.id
        section = .builder
    }
}

struct WardrobeCommands: Commands {
    let nav: AppNavigation

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Photos…") { nav.showPhotoImporter = true }
                .keyboardShortcut("n")
            Button("Add from Link…") { nav.showAddFromLink = true }
                .keyboardShortcut("l")
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.label) { nav.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(WardrobeStore.self) private var store
    @AppStorage("removeBackground") private var removeBackground = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Remove backgrounds from new photos", isOn: $removeBackground)
                Text("Uses Apple's on-device subject lifting. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Library") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.rootURL])
                    }
                }
                if store.hasSamplePieces {
                    LabeledContent("Sample closet") {
                        Button("Remove sample pieces", role: .destructive) { confirmClear = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .confirmationDialog("Remove the sample pieces and the looks that use them?", isPresented: $confirmClear) {
            Button("Remove sample pieces", role: .destructive) { store.clearSampleCloset() }
        }
    }
}
