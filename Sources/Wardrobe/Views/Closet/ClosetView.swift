import SwiftUI
import UniformTypeIdentifiers

struct ClosetView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Photos still being processed, shown as placeholder tiles.
    let importing: Int

    @State private var search = ""
    @State private var family: ColorFamily?
    @State private var category: Category?
    @State private var editing: ClothingItem?
    @State private var dropTargeted = false

    private var baseItems: [ClothingItem] {
        store.items(in: nav.collection)
            .filter { $0.matches(search: search) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    private var visibleItems: [ClothingItem] {
        baseItems.filter { item in
            (family == nil || item.colorFamily == family) && (category == nil || item.category == category)
        }
    }

    private var selectedItem: ClothingItem? {
        if let id = nav.selectedItemID, let item = store.item(id: id) { return item }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            if store.items.isEmpty && importing == 0 {
                ClosetEmptyState()
            } else {
                main
                if let item = selectedItem ?? visibleItems.first {
                    ItemDetailPanel(item: item, onEdit: { editing = item })
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $editing) { item in
            ItemEditorSheet(item: item)
        }
        .onChange(of: nav.collection) { family = nil; category = nil }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 30)
                .padding(.top, 34)
            ColorStrip(items: baseItems, selection: $family)
                .padding(.horizontal, 30)
                .padding(.top, 22)
            categoryChips
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 6)
            grid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nav.collection == .all ? "Closet" : nav.collection.label)
                    .font(.wardrobeTitle)
                    .contentTransition(.opacity)
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 16)
            SearchField(text: $search, prompt: "Search color, brand, name, tag")
                .frame(maxWidth: 260)
            Button { nav.showAddFromLink = true } label: {
                Label("Add from link", systemImage: "link")
            }
            .buttonStyle(.quiet)
            .help("Paste a product page to pull its photo, size and materials (⌘L)")
            Button { nav.showPhotoImporter = true } label: {
                Label("Add photos", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .help("Choose photos; backgrounds are removed automatically (⌘N)")
        }
    }

    private var countLabel: String {
        let items = baseItems
        let n = items.count
        let favorites = items.filter(\.favorite).count
        var parts = ["\(n) \(n == 1 ? "piece" : "pieces")"]
        if favorites > 0 { parts.append("\(favorites) \(favorites == 1 ? "favorite" : "favorites")") }
        if !search.isEmpty { parts.append("matching “\(search)”") }
        return parts.joined(separator: " · ")
    }

    // MARK: Filters

    private var categoryChips: some View {
        let counts = Dictionary(grouping: baseItems.filter { family == nil || $0.colorFamily == family }, by: \.category)
            .mapValues(\.count)
        let total = counts.values.reduce(0, +)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipToggle(label: "All", count: total, isOn: category == nil) { category = nil }
                ForEach(Category.allCases.filter { counts[$0, default: 0] > 0 }) { c in
                    ChipToggle(label: c.label, count: counts[c], isOn: category == c) {
                        category = category == c ? nil : c
                    }
                }
            }
        }
        .animation(Motion.lift, value: category)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18, alignment: .top)],
                      spacing: 22) {
                ForEach(0..<importing, id: \.self) { _ in ImportingTile() }
                ForEach(visibleItems) { item in
                    ItemTile(item: item, isSelected: item.id == (selectedItem ?? visibleItems.first)?.id)
                        .onTapGesture(count: 2) { editing = item }
                        .onTapGesture {
                            withAnimation(Motion.respecting(reduceMotion, Motion.settle)) { nav.selectedItemID = item.id }
                        }
                        .contextMenu { contextMenu(for: item) }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                DropTile(isTargeted: dropTargeted)
            }
            .padding(.horizontal, 30)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .animation(Motion.respecting(reduceMotion, Motion.lift), value: visibleItems.map(\.id))
            if visibleItems.isEmpty && importing == 0 {
                Text(emptyFilterMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
            }
        }
        .scrollContentBackground(.hidden)
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) ?? false }
            guard !images.isEmpty else { return false }
            NotificationCenter.default.post(name: .importPhotos, object: images)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var emptyFilterMessage: String {
        if !search.isEmpty { return "Nothing matches “\(search)”." }
        switch nav.collection {
        case .favorites: return "No favorites yet. Tap the heart on a piece you love."
        case .rarelyWorn: return "Everything has been worn recently. Nice."
        default: return "No pieces match these filters."
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClothingItem) -> some View {
        Button(item.favorite ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(item) }
        Button("Style this piece") { nav.style(item) }
        Button("Edit…") { editing = item }
        if let url = item.sourceURL.flatMap({ URL(string: $0) }) {
            Link("Open product page", destination: url)
        }
        Divider()
        Button("Delete", role: .destructive) {
            if nav.selectedItemID == item.id { nav.selectedItemID = nil }
            withAnimation { store.delete(item) }
        }
    }
}

// MARK: - Pieces

struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
                .font(.system(size: 12.5, weight: .medium))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Theme.green : Theme.line, lineWidth: focused ? 1.5 : 1)
        }
        .animation(Motion.quick, value: focused)
    }
}

struct ItemTile: View {
    let item: ClothingItem
    let isSelected: Bool
    @Environment(WardrobeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 16 : 3, y: hovering ? 12 : 1)
                GarmentView(item: item)
                    .padding(26)
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 5)
                    .offset(y: hovering && !reduceMotion ? -4 : 0)
                    .rotationEffect(.degrees(hovering && !reduceMotion ? -3 : 0))
                    .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if item.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.clay)
                        .padding(10)
                        .accessibilityLabel("Favorite")
                }
            }
            .overlay(alignment: .topLeading) {
                if item.isIdle() {
                    Text(idleLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.amberTonal, in: Capsule())
                        .foregroundStyle(Theme.amber)
                        .padding(9)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.green, lineWidth: isSelected ? 2 : 0)
            }
            .offset(y: hovering && !reduceMotion ? -3 : 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    FabricSwatch(hex: item.colorHex, fabric: item.fabric, size: 10, corner: 5)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.lift, value: hovering)
        .animation(Motion.lift, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var meta: String {
        var parts = [item.displayColorName]
        if item.fabric != .unknown { parts.append(item.fabric.label) } else { parts.append(item.category.singular) }
        return parts.joined(separator: " · ")
    }

    private var idleLabel: String {
        guard let last = item.lastWornAt else { return "Not worn yet" }
        let days = Int(Date.now.timeIntervalSince(last) / 86_400)
        if days >= 60 && days < 120 { return "Idle \(days / 7) wks" }
        return "Idle \(days / 30) mo"
    }
}

private struct ImportingTile: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.linen)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Removing background")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .opacity(pulse ? 1 : 0.7)
            Text("New piece")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct DropTile: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isTargeted ? Theme.green : Theme.inkSecondary)
                .scaleEffect(isTargeted ? 1.15 : 1)
            Text("Drop photos here")
                .font(.system(size: 13, weight: .semibold))
            Text("The background is removed so each piece sits on a clean card.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(isTargeted ? Theme.greenTonal : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? Theme.green : Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .animation(Motion.lift, value: isTargeted)
    }
}

/// The proportional "closet by color" bar. Each segment is a color family,
/// striped with the actual colors of the pieces in it; click to filter.
struct ColorStrip: View {
    let items: [ClothingItem]
    @Binding var selection: ColorFamily?
    @State private var hovered: ColorFamily?

    private var groups: [(family: ColorFamily, hexes: [String])] {
        let byFamily = Dictionary(grouping: items, by: \.colorFamily)
        return ColorFamily.allCases.compactMap { fam -> (family: ColorFamily, hexes: [String])? in
            guard let pieces = byFamily[fam], !pieces.isEmpty else { return nil }
            let hexes = pieces.map(\.colorHex).sorted {
                (RGB(hex: $0)?.luminance ?? 0) > (RGB(hex: $1)?.luminance ?? 0)
            }
            return (fam, hexes)
        }
    }

    var body: some View {
        let groups = self.groups
        let total = max(1, groups.reduce(0) { $0 + $1.hexes.count })
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your closet by color")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(selection.map { "Showing \($0.label.lowercased()). Click again to clear." } ?? "Click a color to filter")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.opacity)
            }
            GeometryReader { geo in
                let gap: CGFloat = 4
                let usable = geo.size.width - gap * CGFloat(max(0, groups.count - 1))
                HStack(spacing: gap) {
                    ForEach(groups, id: \.family) { group in
                        let isDimmed = selection != nil && selection != group.family
                        Button {
                            selection = selection == group.family ? nil : group.family
                        } label: {
                            HStack(spacing: 0) {
                                ForEach(Array(group.hexes.enumerated()), id: \.offset) { _, hex in
                                    Rectangle().fill(Color(hex: hex))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.08))
                            }
                            .scaleEffect(y: hovered == group.family ? 1.18 : 1)
                            .opacity(isDimmed ? 0.3 : 1)
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(18, usable * CGFloat(group.hexes.count) / CGFloat(total)))
                        .onHover { inside in
                            if inside { hovered = group.family } else if hovered == group.family { hovered = nil }
                        }
                        .help("\(group.family.label): \(group.hexes.count)")
                        .accessibilityLabel("\(group.family.label), \(group.hexes.count) pieces")
                        .accessibilityAddTraits(selection == group.family ? .isSelected : [])
                    }
                }
            }
            .frame(height: 22)
            GeometryReader { geo in
                let gap: CGFloat = 4
                let usable = geo.size.width - gap * CGFloat(max(0, groups.count - 1))
                HStack(spacing: gap) {
                    ForEach(groups, id: \.family) { group in
                        Text(group.family.label)
                            .font(.system(size: 11.5, weight: selection == group.family ? .semibold : .regular))
                            .foregroundStyle(selection == group.family ? Theme.ink : Theme.inkSecondary)
                            .lineLimit(1)
                            .frame(width: max(18, usable * CGFloat(group.hexes.count) / CGFloat(total)), alignment: .leading)
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
        }
        .animation(Motion.lift, value: selection)
        .animation(Motion.lift, value: hovered)
        .animation(Motion.settle, value: items.map(\.id))
    }
}
