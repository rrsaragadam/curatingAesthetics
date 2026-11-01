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
        "Finding a photo of just the piece",
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
    @State private var photos: [PagePhoto] = []
    @State private var chosenPhoto: UUID?
    @State private var photoTask: Task<Void, Never>?
    /// Set when the store wouldn't share its page, so the details come from
    /// the link and the photo from the person's browser.
    @State private var blockedHost: String?
    @State private var dropTargeted = false
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

            Spacer(minLength: 0)

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
        // The sheet window keeps the size it opens at, so it opens tall enough
        // for the preview rather than growing into it.
        .frame(width: 640, height: 580, alignment: .top)
        .background(Theme.panel)
        .animation(Motion.respecting(reduceMotion, Motion.settle), value: phase)
        .onAppear {
            if let given = nav.linkToAdd {
                nav.linkToAdd = nil
                link = given
                fetch()
                return
            }
            if let s = NSPasteboard.general.string(forType: .string), ProductImporter.normalizedURL(from: s) != nil,
               s.lowercased().hasPrefix("http") {
                link = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            linkFocused = true
        }
        .onDisappear { task?.cancel(); photoTask?.cancel() }
    }

    /// One photo from the product page, checked for a person wearing it.
    private struct PagePhoto: Identifiable {
        let id = UUID()
        let data: Data
        let thumbnail: NSImage
        let check: ImageProcessor.PhotoCheck
        /// Shows the color picked in the link, judging by its file name.
        let inLinkColor: Bool

        /// Where to crop for `category` when a model is wearing the piece.
        func crop(for category: Category) -> CGRect? {
            check.hasPerson ? check.garmentRegion(for: category) : nil
        }
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
        VStack(alignment: .leading, spacing: 14) {
            if let blockedHost { blockedNote(blockedHost) }
            previewBody
        }
    }

    private func blockedNote(_ host: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.amber)
            Text("\(host) didn't share this product's details with Wardrobe, so check the ones below. For the photo, drag it here from your browser, or copy it (Control-click, Copy Image) and press Paste photo.")
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amberTonal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewBody: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.linen)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.green, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(dropTargeted ? 1 : 0)
                Group {
                    if let previewImage {
                        Image(nsImage: previewImage).resizable().interpolation(.high).scaledToFit()
                    } else {
                        GarmentIllustration(category: draft.category, hex: draft.colorHex, fabric: draft.fabric)
                            .opacity(blockedHost == nil ? 1 : 0.35)
                    }
                }
                .padding(20)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 8)
                if backgroundRemoved {
                    Label(chosenHasPerson ? "Cropped to the piece" : "Background removed",
                          systemImage: chosenHasPerson ? "person.crop.rectangle" : "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: Capsule())
                        .foregroundStyle(Theme.green)
                        .padding(10)
                }
            }
            .frame(width: 200, height: 220)
            .overlay {
                if photoTask != nil {
                    ProgressView().controlSize(.small)
                } else if blockedHost != nil && previewImage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 22))
                        Button("Paste photo", action: pastePhoto).buttonStyle(.quiet)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                }
            }
            .onDrop(of: [.image, .url], isTargeted: $dropTargeted) { providers in
                loadDropped(providers)
                return true
            }
            .overlay(alignment: .bottom) {
                if photos.count > 1 { photoStrip.offset(y: 46) }
            }
            .padding(.bottom, photos.count > 1 ? 46 : 0)

            VStack(alignment: .leading, spacing: 10) {
                if !brandLine.isEmpty {
                    Text(brandLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                // Looks like a field so it's clear the store's name can be changed.
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(Typeface.display(20))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line)
                    }
                    .help("Rename the piece")

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
                    HStack(spacing: 10) {
                        if draft.category == .shoes {
                            Text("Type").foregroundStyle(Theme.inkTertiary).frame(width: 72, alignment: .leading)
                            Picker("Type", selection: $draft.shoeType) {
                                ForEach(ShoeType.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        } else {
                            Text("Silhouette").foregroundStyle(Theme.inkTertiary).frame(width: 72, alignment: .leading)
                            Picker("Silhouette", selection: $draft.silhouette) {
                                ForEach(Silhouette.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
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

    private var chosenHasPerson: Bool {
        photos.first { $0.id == chosenPhoto }?.check.hasPerson ?? false
    }

    /// The other photos on the page, to pick a better one than the guess.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(photos) { photo in
                    Button { choose(photo) } label: {
                        Image(nsImage: photo.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(chosenPhoto == photo.id ? Theme.green : Theme.line,
                                                  lineWidth: chosenPhoto == photo.id ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(photo.check.hasPerson ? "Model photo: Wardrobe crops to the piece" : "Product photo")
                    .accessibilityLabel(photo.check.hasPerson ? "Model photo" : "Product photo")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(width: 200, height: 42)
    }

    private func choose(_ photo: PagePhoto) {
        guard chosenPhoto != photo.id else { return }
        chosenPhoto = photo.id
        photoTask?.cancel()
        photoTask = Task { @MainActor in
            let processed = try? await ImageProcessor.process(imageData: photo.data, removeBackground: removeBackground,
                                                              crop: photo.crop(for: draft.category))
            guard !Task.isCancelled else { return }
            if let processed { apply(processed) }
            photoTask = nil
        }
    }

    /// The store refused the page: fill in what the link itself says and let
    /// the person bring the photo.
    private func startFromLinkOnly(_ url: URL) {
        let host = ProductDetails.host(of: url)
        var item = ClothingItem(name: ProductImporter.name(fromLink: url),
                                category: CategoryGuesser.guess(from: url.path()) ?? .top)
        item.brand = ProductImporter.brand(fromHost: host)
        item.sourceURL = url.absoluteString
        item.shoeType = ShoeType.guess(from: url.path()) ?? .unknown
        draft = item
        sizes = []
        photos = []
        png = nil
        previewImage = nil
        backgroundRemoved = false
        blockedHost = host
        brandLine = [item.brand, host].filter { !$0.isEmpty }.joined(separator: " · ")
        withAnimation(Motion.respecting(reduceMotion, Motion.settle)) { phase = .preview }
    }

    private func pastePhoto() {
        let board = NSPasteboard.general
        if let image = NSImage(pasteboard: board) {
            usePhoto(image)
        } else if let text = board.string(forType: .string), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.hasPrefix("http") == true {
            downloadPhoto(url)
        }
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in usePhoto(image) }
            }
        } else if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.isFileURL, let image = NSImage(contentsOf: url) { usePhoto(image) } else { downloadPhoto(url) }
                }
            }
        }
    }

    private func downloadPhoto(_ url: URL) {
        Task { @MainActor in
            let referer = URL(string: draft.sourceURL ?? "") ?? url
            if let data = try? await ProductImporter.downloadImage(url, referer: referer), let image = NSImage(data: data) {
                usePhoto(image, data: data)
            }
        }
    }

    /// Adds a photo the person brought and shows it like a page photo.
    private func usePhoto(_ image: NSImage, data: Data? = nil) {
        guard let data = data ?? image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        else { return }
        let category = draft.category
        Task { @MainActor in
            guard let check = await ImageProcessor.check(imageData: data, category: category) else { return }
            let photo = PagePhoto(data: data, thumbnail: image, check: check, inLinkColor: true)
            photos.append(photo)
            if let color = check.pieceColor, draft.colorName.isEmpty { draft.colorName = ColorNamer.name(for: color) }
            choose(photo)
        }
    }

    private func apply(_ processed: ProcessedImage) {
        png = processed.png
        previewImage = NSImage(data: processed.png)
        backgroundRemoved = processed.backgroundRemoved
        if let color = processed.dominantColor {
            draft.colorHex = color.hex
        }
    }

    /// Downloads the page's photos (the color in the link first) and checks
    /// each for a person, stopping at the first that shows just the piece.
    private func gatherPhotos(_ details: ProductDetails, category: Category, from url: URL) async -> [PagePhoto] {
        var found: [PagePhoto] = []
        for candidate in ProductImporter.photoOrder(details.imageURLs, pageURL: url).prefix(14) {
            if Task.isCancelled { break }
            guard let data = try? await ProductImporter.downloadImage(candidate, referer: url),
                  let image = NSImage(data: data),
                  let check = await ImageProcessor.check(imageData: data, category: category) else { continue }
            found.append(PagePhoto(data: data, thumbnail: image, check: check,
                                   inLinkColor: ProductImporter.photo(candidate, matchesColorIn: url)))
        }
        return found
    }

    /// The piece's color in the link: as worn in its model photos, or the
    /// page's color word.
    private func referenceColor(in photos: [PagePhoto], colorWord: String) -> RGB? {
        photos.first(where: \.inLinkColor)?.check.pieceColor
            ?? ColorNamer.hex(forColorWord: colorWord).flatMap { RGB(hex: $0) }
    }

    /// The photo to start with. A shot of just the piece beats a model photo
    /// when it's in the link's color: named for it, or matching the piece's
    /// color in the link's model photos (or the page's color word). Failing
    /// that, the model photo in the link's color, cropped to the piece.
    private func bestPhoto(in photos: [PagePhoto], category: Category, reference: RGB?, url: URL) -> PagePhoto? {
        let hasColor = !ProductImporter.colorCodes(in: url).isEmpty || reference != nil
        func rightColor(_ photo: PagePhoto) -> Bool {
            if photo.inLinkColor { return true }
            guard let reference, let color = photo.check.pieceColor else { return !hasColor }
            return color.distance(to: reference) < 12
        }
        let products = photos.filter(\.check.isProductShot)
        // A product shot of unknown color only beats the model photos when
        // none of them is in the link's color either.
        let inColor = photos.filter(\.inLinkColor)
        return products.first(where: rightColor)
            ?? inColor.first { $0.crop(for: category) != nil }
            ?? (inColor.isEmpty ? products.first : nil)
            ?? photos.first { $0.crop(for: category) != nil }
            ?? inColor.first
            ?? photos.first
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
            let details: ProductDetails
            do {
                details = try await ProductImporter.fetchDetails(from: url)
            } catch ProductImporter.Failure.blocked, ProductImporter.Failure.nothingFound {
                // Some stores (adidas) turn apps away or send a page with no product on it.
                startFromLinkOnly(url)
                return
            }
            try Task.checkCancellation()

            setStep(1)
            let category = details.categoryGuess ?? .top
            var pagePhotos = await gatherPhotos(details, category: category, from: url)
            let reference = referenceColor(in: pagePhotos, colorWord: details.colorWord)
            // Photos clearly showing another color (a model in the beige pair
            // when the link is for black) aren't worth offering.
            if let reference {
                pagePhotos.removeAll { photo in
                    guard !photo.inLinkColor, let color = photo.check.pieceColor else { return false }
                    return color.distance(to: reference) > 40
                }
            }
            let best = bestPhoto(in: pagePhotos, category: category, reference: reference, url: url)
            try Task.checkCancellation()

            setStep(2)
            var processed: ProcessedImage?
            if let best {
                processed = try? await ImageProcessor.process(imageData: best.data, removeBackground: removeBackground,
                                                              crop: best.crop(for: category))
            }
            try Task.checkCancellation()

            setStep(3)
            var item = ClothingItem(name: details.name.isEmpty ? "New piece" : details.name,
                                    category: details.categoryGuess ?? processed?.categoryGuess ?? .top)
            item.brand = details.brand
            item.material = details.material
            item.care = details.care
            item.fabric = details.fabricGuess ?? .unknown
            item.silhouette = details.silhouetteGuess ?? .unknown
            item.shoeType = ShoeType.guess(from: details.name) ?? ShoeType.guess(from: details.breadcrumbs) ?? .unknown
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
            photos = pagePhotos
            chosenPhoto = best?.id
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

