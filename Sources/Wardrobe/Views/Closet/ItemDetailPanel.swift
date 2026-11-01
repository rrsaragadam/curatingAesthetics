import SwiftUI

/// The right-hand panel for the selected piece.
struct ItemDetailPanel: View {
    let item: ClothingItem
    let onEdit: () -> Void
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            hero
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name)
                            .font(Typeface.display(23))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: item.colorHex))
                                .overlay { Circle().strokeBorder(.black.opacity(0.12)) }
                                .frame(width: 10, height: 10)
                            Text(metaLine)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }

                    HStack(spacing: 10) {
                        StatBox(value: "\(item.timesWorn)", label: item.timesWorn == 1 ? "time worn" : "times worn")
                        StatBox(value: sinceLastWorn, label: item.lastWornAt == nil ? "worn yet" : "since last worn")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Texture", value: item.fabric == .unknown ? "" : item.fabric.label,
                                  swatch: AnyView(FabricSwatch(hex: item.colorHex, fabric: item.fabric, size: 14)))
                        DetailRow(label: "Material", value: item.material)
                        DetailRow(label: "Size", value: item.size)
                        if !item.care.isEmpty { DetailRow(label: "Care", value: item.care) }
                        DetailRow(label: "Seasons", value: Season.describe(item.seasons))
                        DetailRow(label: "Dress code", value: item.formality.label)
                        if !visibleTags.isEmpty { DetailRow(label: "Tags", value: visibleTags.joined(separator: ", ")) }
                        sourceRow
                    }

                    outfitsSection
                }
                .padding(20)
            }
            .scrollIndicators(.never)

            HStack(spacing: 8) {
                Button { nav.style(item) } label: {
                    Text("Style this piece").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                Button("Edit", action: onEdit)
                    .buttonStyle(.quiet)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Divider().overlay(Theme.line) }
        }
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            Theme.linen
            GarmentView(item: item)
                .padding(34)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
                .id(item.id)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(y: -16).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                    removal: .opacity))
            Button {
                withAnimation(Motion.lift) { store.toggleFavorite(item) }
            } label: {
                Image(systemName: item.favorite ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.clay)
                    .frame(width: 34, height: 34)
                    .background(Theme.card, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(item.favorite ? "Remove from favorites" : "Add to favorites")
        }
        .frame(height: 250)
        .clipped()
        .animation(Motion.settle, value: item.id)
    }

    private var visibleTags: [String] { item.tags.filter { $0 != SampleCloset.tag } }

    private var metaLine: String {
        var parts = [item.displayColorName, item.category.singular]
        if !item.brand.isEmpty { parts.append(item.brand) }
        return parts.joined(separator: " · ")
    }

    private var sinceLastWorn: String {
        guard let last = item.lastWornAt else { return "Not" }
        return Self.shortInterval(since: last)
    }

    static func shortInterval(since date: Date, now: Date = .now) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        switch days {
        case 0: return "Today"
        case 1..<14: return "\(days)d"
        case 14..<70: return "\(days / 7) wk"
        case 70..<365: return "\(days / 30) mo"
        default: return "\(days / 365) yr"
        }
    }

    @ViewBuilder
    private var sourceRow: some View {
        if let s = item.sourceURL, let url = URL(string: s) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Source")
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(width: 72, alignment: .leading)
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Text(item.sourceHost ?? "Product page")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.green)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
        } else {
            DetailRow(label: "Source", value: item.imageFile == nil ? "Added by hand" : "Added from a photo")
        }
    }

    private var outfitsSection: some View {
        let looks = store.outfits(containing: item)
        return VStack(alignment: .leading, spacing: 8) {
            Text("In your outfits")
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 4)
            if looks.isEmpty {
                Text("Not in a saved outfit yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(looks) { look in
                    Button {
                        nav.open(look)
                    } label: {
                        HStack(spacing: 10) {
                            PaletteBar(hexes: store.items(of: look).map(\.colorHex), height: 10)
                                .frame(width: 44)
                            Text(look.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in the outfit builder")
                }
            }
        }
    }
}

private struct StatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typeface.display(22))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Shown until the first piece arrives.
struct ClosetEmptyState: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @State private var appeared = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: -18) {
                GarmentIllustration(category: .outerwear, hex: "#8A5A35", fabric: .canvas)
                    .frame(width: 120).rotationEffect(.degrees(-8))
                GarmentIllustration(category: .top, hex: "#DCE6F2", fabric: .oxford)
                    .frame(width: 130).offset(y: -10)
                GarmentIllustration(category: .bottom, hex: "#3B4F6E", fabric: .denim)
                    .frame(width: 116).rotationEffect(.degrees(7))
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 8)
            .offset(y: appeared ? 0 : -18)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text("Start your closet")
                    .font(Typeface.display(30))
                Text("Drop in photos of your clothes and shoes. Wardrobe lifts each piece off its background so it sits on a clean card. Or paste a product link to pull the photo, size and materials.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 10) {
                Button { nav.showPhotoImporter = true } label: { Label("Add photos", systemImage: "plus") }
                    .buttonStyle(.primary)
                Button { nav.showAddFromLink = true } label: { Label("Add from link", systemImage: "link") }
                    .buttonStyle(.quiet)
            }

            Button("Explore with a sample closet first") {
                withAnimation(Motion.settle) { store.loadSampleCloset() }
            }
            .buttonStyle(.link)
            .foregroundStyle(Theme.green)
            .font(.system(size: 13))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(dropTargeted ? Theme.green : .clear, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .padding(20)
        }
        .dropDestination(for: URL.self) { urls, _ in
            NotificationCenter.default.post(name: .importPhotos, object: urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .onAppear { withAnimation(Motion.settle.delay(0.1)) { appeared = true } }
    }
}
