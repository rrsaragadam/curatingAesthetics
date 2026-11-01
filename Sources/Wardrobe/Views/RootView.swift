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
                .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 260)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch nav.section {
                case .closet: ClosetView(importing: importing)
                case .builder: BuilderView()
                case .lookbook: LookbookView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
