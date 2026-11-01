import AppKit
import SwiftUI

/// Paste a product page; Wardrobe pulls the photo (and lifts it off its
/// background), the size range, materials and care, so outfits can account
/// for texture.
struct AddFromLinkSheet: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("removeBackground") private var removeBackground = true

    private enum Phase: Equatable {
        case input
        case loading(step: Int)
        case preview
        case failed(String)
    }

    private static let steps = [
        "Reading the product page",
        "Downloading the photo",
        "Removing the background",
        "Pulling size, material and care",
    ]

    @State private var link = ""
    @State private var phase: Phase = .input
    @State private var draft = ClothingItem(name: "", category: .top)
    @State private var sizes: [String] = []
    @State private var png: Data?
    @State private var previewImage: NSImage?
    @State private var backgroundRemoved = false
    @State private var brandLine = ""
    @State private var task: Task<Void, Never>?
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add from a link")
                    .font(Typeface.display(24))
                Text("Paste a product page. Wardrobe pulls the photo, size, materials and care details, so outfits can account for texture.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "link").foregroundStyle(Theme.inkSecondary)
                    TextField("https://store.com/products/waffle-henley", text: $link)
                        .textFieldStyle(.plain)
                        .focused($linkFocused)
                        .onSubmit(fetch)
                        .disabled(isLoading)
                }
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(linkFocused ? Theme.green : Theme.line, lineWidth: linkFocused ? 1.5 : 1)
                }
                if phase != .preview {
                    Button("Fetch details", action: fetch)
                        .buttonStyle(.primary)
                        .disabled(ProductImporter.normalizedURL(from: link) == nil || isLoading)
                }
            }

            Group {
                switch phase {
                case .input: promises
                case .loading(let step): progress(step)
                case .preview: preview
                case .failed(let message): failure(message)
                }
            }
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))

            HStack {
                Spacer()
                Button("Cancel") { task?.cancel(); dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                if phase == .preview {
                    Button("Add to closet", action: add)
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(26)
        .frame(width: 640)
        .background(Theme.panel)
        .animation(Motion.respecting(reduceMotion, Motion.settle), value: phase)
        .onAppear {
            if let s = NSPasteboard.general.string(forType: .string), ProductImporter.normalizedURL(from: s) != nil,
               s.lowercased().hasPrefix("http") {
                link = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            linkFocused = true
        }
        .onDisappear { task?.cancel() }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    // MARK: Phases

    private var promises: some View {
        HStack(spacing: 16) {
            Label("Photo, background removed", systemImage: "photo")
            Label("Size and fit", systemImage: "ruler")
            Label("Material and texture", systemImage: "square.grid.3x3")
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.green)
        .padding(.vertical, 4)
    }

    private func progress(_ current: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 10) {
                    ZStack {
                        if index < current {
                            Circle().fill(Theme.green)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.onGreen)
                        } else if index == current {
                            ProgressView().controlSize(.small)
                        } else {
                            Circle().strokeBorder(Theme.line, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .transition(.scale.combined(with: .opacity))
                    Text(label)
                        .font(.system(size: 13, weight: index == current ? .semibold : .regular))
                        .foregroundStyle(index <= current ? Theme.ink : Theme.inkTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.steps[min(current, Self.steps.count - 1)])
    }

    private func failure(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add a photo instead") {
                    dismiss()
                    nav.showPhotoImporter = true
                }
                .buttonStyle(.link)
                .foregroundStyle(Theme.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberTonal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.linen)
                Group {
                    if let previewImage {
                        Image(nsImage: previewImage).resizable().interpolation(.high).scaledToFit()
                    } else {
                        GarmentIllustration(category: draft.category, hex: draft.colorHex, fabric: draft.fabric)
                    }
                }
                .padding(20)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 8)
                if backgroundRemoved {
                    Label("Background removed", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: Capsule())
                        .foregroundStyle(Theme.green)
                        .padding(10)
                }
            }
            .frame(width: 200, height: 220)

            VStack(alignment: .leading, spacing: 10) {
                if !brandLine.isEmpty {
                    Text(brandLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(Typeface.display(20))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Texture").foregroundStyle(Theme.inkTertiary).frame(width: 72, alignment: .leading)
                        FabricSwatch(hex: draft.colorHex, fabric: draft.fabric, size: 14)
                        Picker("Texture", selection: $draft.fabric) {
                            ForEach(Fabric.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    DetailRow(label: "Material", value: draft.material)
                    DetailRow(label: "Color", value: draft.displayColorName,
                              swatch: AnyView(Circle().fill(Color(hex: draft.colorHex)).frame(width: 10, height: 10)))
                    if !draft.care.isEmpty { DetailRow(label: "Care", value: draft.care) }
                    HStack(spacing: 10) {
                        Text("Category").foregroundStyle(Theme.inkTertiary).frame(width: 72, alignment: .leading)
                        Picker("Category", selection: $draft.category) {
                            ForEach(Category.allCases) { Text($0.singular).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Your size").foregroundStyle(Theme.inkTertiary).frame(width: 72, alignment: .leading)
                        if sizes.isEmpty {
                            TextField("e.g. M", text: $draft.size)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(sizes, id: \.self) { size in
                                        ChipToggle(label: size, isOn: draft.size == size) { draft.size = size }
                                    }
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 12.5))

                Text("You can edit any of this later.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    // MARK: Actions

    private func fetch() {
        guard let url = ProductImporter.normalizedURL(from: link), !isLoading else { return }
        task?.cancel()
        task = Task { await run(url) }
    }

    private func setStep(_ step: Int) {
        withAnimation(Motion.respecting(reduceMotion, Motion.lift)) { phase = .loading(step: step) }
    }

    @MainActor
    private func run(_ url: URL) async {
        setStep(0)
        do {
            let details = try await ProductImporter.fetchDetails(from: url)
            try Task.checkCancellation()

            setStep(1)
            var imageData: Data?
            for candidate in details.imageURLs.prefix(3) {
                if let data = try? await ProductImporter.downloadImage(candidate, referer: url), NSImage(data: data) != nil {
                    imageData = data
                    break
                }
            }
            try Task.checkCancellation()

            setStep(2)
            var processed: ProcessedImage?
            if let imageData {
                processed = try? await ImageProcessor.process(imageData: imageData, removeBackground: removeBackground)
            }
            try Task.checkCancellation()

            setStep(3)
            var item = ClothingItem(name: details.name.isEmpty ? "New piece" : details.name,
                                    category: details.categoryGuess ?? processed?.categoryGuess ?? .top)
            item.brand = details.brand
            item.material = details.material
            item.care = details.care
            item.fabric = details.fabricGuess ?? .unknown
            item.sourceURL = url.absoluteString
            if !details.colorWord.isEmpty {
                item.colorName = details.colorWord.split(separator: "/").first.map {
                    String($0).trimmingCharacters(in: .whitespaces).lowercased().capitalizedFirst
                } ?? ""
            }
            if let fromPhoto = processed?.dominantColor {
                item.colorHex = fromPhoto.hex
                if item.colorName.isEmpty { item.colorName = ColorNamer.name(for: fromPhoto) }
            } else if let hex = ColorNamer.hex(forColorWord: details.colorWord) {
                item.colorHex = hex
            }
            if details.sizes.count == 1 { item.size = details.sizes[0] }

            draft = item
            sizes = details.sizes
            png = processed?.png
            previewImage = processed.flatMap { NSImage(data: $0.png) }
            backgroundRemoved = processed?.backgroundRemoved ?? false
            brandLine = [details.brand, details.host].filter { !$0.isEmpty }.joined(separator: " · ")
            // Let the last check land before revealing the preview.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
            withAnimation(Motion.respecting(reduceMotion, Motion.settle)) { phase = .preview }
        } catch is CancellationError {
            return
        } catch {
            withAnimation { phase = .failed(error.localizedDescription) }
        }
    }

    private func add() {
        var item = draft
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.addedAt = .now
        let added = store.addImported(item, png: png)
        nav.section = .closet
        nav.collection = .all
        withAnimation(Motion.settle) { nav.selectedItemID = added.id }
        dismiss()
    }
}
