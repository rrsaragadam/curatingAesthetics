import Combine
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @AppStorage("removeBackground") private var removeBackground = true
    @State private var importing = 0

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            Sidebar()
                .toolbar(removing: .sidebarToggle)
                // Must come after `.toolbar(removing:)`, or the width is ignored and
                // the sidebar falls back to a narrow default.
                .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 260)
        } detail: {
            Group {
                switch nav.section {
                case .closet: ClosetView(importing: importing)
                case .builder: BuilderView()
                case .lookbook: LookbookView()
                }
            }
            // minHeight 0 keeps a tall page from making the column taller than
            // the window, which pushes every screen's top under the title bar.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(Theme.ground)
            .foregroundStyle(Theme.ink)
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(isPresented: $nav.showPhotoImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importPhotos(urls) }
        }
        .sheet(isPresented: $nav.showAddFromLink) {
            AddFromLinkSheet()
        }
        .sheet(isPresented: $nav.showStylistGaps) {
            StylistGapsSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .importPhotos)) { note in
            if let urls = note.object as? [URL] { importPhotos(urls) }
        }
    }

    private func importPhotos(_ urls: [URL]) {
        nav.section = .closet
        importing += urls.count
        Task {
            for url in urls {
                if let item = await store.importPhoto(at: url, removeBackground: removeBackground) {
                    withAnimation(Motion.settle) { nav.selectedItemID = item.id }
                }
                importing -= 1
            }
        }
    }
}

extension Notification.Name {
    /// Posted with `[URL]` when photos are dropped anywhere in the closet.
    static let importPhotos = Notification.Name("Wardrobe.importPhotos")
}
