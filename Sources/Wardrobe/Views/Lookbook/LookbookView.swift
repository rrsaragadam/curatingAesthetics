import SwiftUI

struct LookbookView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: Occasion?
    @State private var confirmDelete: Outfit?

    private var visible: [Outfit] {
        store.outfits
            .filter { filter == nil || $0.occasion == filter }
            .sorted { ($0.lastWorn ?? $0.createdAt) > ($1.lastWorn ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lookbook").font(.wardrobeTitle)
                    Text("Your saved outfits. Tap “Worn today” and it lands on this week.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.top, 30)

                WeekStrip()

                if store.outfits.isEmpty {
                    emptyState
                } else {
                    filters
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 20, alignment: .top)],
                              spacing: 20) {
                        ForEach(visible) { outfit in
                            LookCard(outfit: outfit)
                                .contextMenu {
                                    Button("Open in builder") { nav.open(outfit) }
                                    if outfit.wasWorn(on: .now) {
                                        Button("Not worn today after all") { store.unmarkWorn(outfit) }
                                    }
                                    Divider()
                                    Button("Delete look", role: .destructive) { confirmDelete = outfit }
                                }
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                    .animation(Motion.respecting(reduceMotion, Motion.lift), value: visible.map(\.id))
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Delete \(confirmDelete?.name ?? "this look")?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete look", role: .destructive) {
                if let outfit = confirmDelete { withAnimation { store.delete(outfit) } }
                confirmDelete = nil
            }
        } message: {
            Text("The pieces stay in your closet.")
        }
    }

    private var filters: some View {
        let counts = Dictionary(grouping: store.outfits, by: \.occasion).mapValues(\.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipToggle(label: "All looks", count: store.outfits.count, isOn: filter == nil) { filter = nil }
                ForEach(Occasion.allCases.filter { counts[$0, default: 0] > 0 }) { o in
                    ChipToggle(label: o.label, count: counts[o], isOn: filter == o) { filter = filter == o ? nil : o }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No saved looks yet").font(Typeface.display(20))
            Text("Build one in the outfit builder and save it here. Then log the days you wear it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
            Button("Open the outfit builder") { nav.section = .builder }
                .buttonStyle(.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - This week

private struct WeekStrip: View {
    @Environment(WardrobeStore.self) private var store

    var body: some View {
        let week = store.week()
        let logged = week.filter { $0.outfit != nil }
        let distinct = Set(logged.compactMap { $0.outfit?.id }).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(Typeface.display(18))
                Spacer()
                Text(logged.isEmpty ? "Nothing logged yet"
                     : "\(logged.count) of 7 days logged · \(distinct) \(distinct == 1 ? "look" : "different looks")")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                ForEach(week, id: \.day) { entry in
                    DayCell(day: entry.day, outfit: entry.outfit)
                }
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line) }
    }
}

private struct DayCell: View {
    let day: Date
    let outfit: Outfit?
    @Environment(WardrobeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isFuture: Bool { day > .now && !isToday }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(isToday ? "Today" : day.formatted(.dateTime.day()))
                    .font(.system(size: 11.5, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Theme.green : Theme.inkTertiary)
            }
            ZStack {
                if let outfit {
                    VStack(alignment: .leading, spacing: 6) {
                        PaletteBar(hexes: store.items(of: outfit).map(\.colorHex), height: 26)
                        Text(outfit.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id(outfit.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: -14).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .top)),
                        removal: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.2, dash: isFuture ? [] : [4, 3]))
                        .frame(height: 26)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: 64, alignment: .top)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(isToday ? Theme.greenTonal.opacity(0.6) : Theme.ground,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isFuture ? 0.6 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: outfit?.id)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Look card

private struct LookCard: View {
    let outfit: Outfit
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @State private var hovering = false

    var body: some View {
        let pieces = store.items(of: outfit)
        VStack(alignment: .leading, spacing: 0) {
            LookCollage(pieces: pieces, spread: hovering)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .background(Theme.linen)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { nav.open(outfit) }

            PaletteBar(hexes: pieces.map(\.colorHex), height: 6)
                .clipShape(Rectangle())
                .padding(.horizontal, -1)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(outfit.name)
                        .font(Typeface.display(17))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    StarRating(rating: outfit.rating) { new in
                        var copy = outfit
                        copy.rating = copy.rating == new ? 0 : new
                        withAnimation(Motion.lift) { store.update(copy) }
                    }
                }
                HStack(spacing: 8) {
                    Text(outfit.occasion.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.greenTonal, in: Capsule())
                        .foregroundStyle(Theme.green)
                    Text(wornLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Spacer(minLength: 4)
                    if outfit.wasWorn(on: .now) {
                        Label("Today's look", systemImage: "sun.max.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { store.markWorn(outfit) }
                        } label: {
                            Label("Worn today", systemImage: "sun.max")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .buttonStyle(WardrobeButtonStyle(kind: .quiet, compact: true))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line) }
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.03), radius: hovering ? 18 : 2, y: hovering ? 12 : 1)
        .offset(y: hovering ? -3 : 0)
        .onHover { hovering = $0 }
        .animation(Motion.lift, value: hovering)
    }

    private var wornLine: String {
        let n = outfit.timesWorn
        guard n > 0, let last = outfit.lastWorn else { return "Not worn yet" }
        let when = Calendar.current.isDateInToday(last) ? "today" : ItemDetailPanel.shortInterval(since: last) + " ago"
        return "Worn \(n)× · \(when)"
    }
}

/// The pieces of a look scattered on linen; they fan out a little on hover.
private struct LookCollage: View {
    let pieces: [ClothingItem]
    let spread: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let slots: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        (-0.24, -0.08, 0.62, -6), (0.22, -0.12, 0.6, 5), (-0.06, 0.18, 0.58, -2), (0.3, 0.26, 0.42, 8), (-0.3, 0.3, 0.4, -9),
    ]

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                ForEach(Array(ordered.prefix(5).enumerated()), id: \.element.id) { index, item in
                    let slot = Self.slots[index]
                    let fan: CGFloat = spread && !reduceMotion ? 1.12 : 1
                    GarmentView(item: item)
                        .frame(width: h * slot.size, height: h * slot.size)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 5)
                        .rotationEffect(.degrees(slot.angle * (spread && !reduceMotion ? 1.5 : 1)))
                        .offset(x: slot.x * h * fan, y: slot.y * h * fan)
                }
            }
            .frame(width: geo.size.width, height: h)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pieces.map(\.name).joined(separator: ", "))
    }

    /// Outerwear and tops first so they sit at the back-top of the collage.
    private var ordered: [ClothingItem] {
        let rank: [Category: Int] = [.outerwear: 0, .jacket: 0, .top: 1, .dress: 1, .bottom: 2, .shoes: 3, .accessory: 4]
        return pieces.sorted { rank[$0.category, default: 5] < rank[$1.category, default: 5] }
    }
}

private struct StarRating: View {
    let rating: Int
    let onRate: (Int) -> Void
    @State private var hoverValue: Int?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { value in
                Button { onRate(value) } label: {
                    Image(systemName: value <= (hoverValue ?? rating) ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(value <= (hoverValue ?? rating) ? Theme.amber : Theme.inkTertiary.opacity(0.6))
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoverValue = value } else if hoverValue == value { hoverValue = nil }
                }
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rating == 0 ? "Not rated" : "Rated \(rating) of 5")
    }
}
