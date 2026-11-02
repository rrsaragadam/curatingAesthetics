import SwiftUI

struct Sidebar: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            wordmark
                .padding(.top, 34)   // clears the window's traffic lights
                .padding(.bottom, 18)

            ForEach(AppSection.allCases) { section in
                SidebarRow(label: section.label, symbol: section.symbol,
                           isSelected: nav.section == section && !(section == .closet && nav.collection != .all)) {
                    nav.section = section
                    if section == .closet { nav.collection = .all }
                }
            }

            Text("Collections")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.forestMuted)
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .padding(.bottom, 6)

            ForEach([ClosetCollection.favorites, .inSeason, .rarelyWorn]) { collection in
                SidebarRow(label: collection.label, symbol: collection.symbol,
                           count: store.items(in: collection).count,
                           isSelected: nav.section == .closet && nav.collection == collection) {
                    nav.section = .closet
                    nav.collection = collection
                }
            }

            Spacer(minLength: 20)

            StylistCard()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.forest.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            // Three folded garments in the closet's own colors.
            VStack(spacing: 2.5) {
                Capsule().fill(Color(hex: "#C9A27A")).frame(width: 18, height: 5)
                Capsule().fill(Color(hex: "#A8D5B5")).frame(width: 18, height: 5)
                Capsule().fill(Color(hex: "#DCE6F2")).frame(width: 18, height: 5)
            }
            .rotationEffect(.degrees(-8))
            .accessibilityHidden(true)
            Text("Wardrobe")
                .font(Typeface.display(21))
                .foregroundStyle(Theme.forestText)
        }
        .padding(.horizontal, 12)
    }
}

private struct SidebarRow: View {
    let label: String
    let symbol: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.mint : Theme.forestMuted)
                Text(label)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Theme.forestText)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.forestMuted)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.11 : (hovering ? 0.06 : 0)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.lift, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The on-device stylist: a shortcut to a suggested look in the builder, or
/// why it's unavailable.
private struct StylistCard: View {
    @Environment(AppNavigation.self) private var nav
    private let isAvailable = StylistProvider.current != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stylist", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.forestText)
                Spacer()
                Text(isAvailable ? "On device" : "Off")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(Theme.forestMuted)
            }
            Text(isAvailable ? "Looks from your closet, put together privately on this Mac."
                             : StylistProvider.unavailableReason ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.forestMuted)
                .fixedSize(horizontal: false, vertical: true)
            if isAvailable {
                Button("Suggest a look") { nav.askStylist() }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.forestText)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
    }
}
