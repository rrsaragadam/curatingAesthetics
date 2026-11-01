import SwiftUI

/// Plain-language notes about a combination's colors and textures. Rule based
/// for now; the future stylist (see `Stylist`) can replace or extend these.
enum OutfitNotes {
    static func texture(for items: [ClothingItem]) -> String {
        let known = items.filter { $0.fabric != .unknown }
        guard !known.isEmpty else { return "Set a texture on these pieces to see how they play together." }
        let textured = known.filter(\.fabric.isTextured).count
        let smooth = known.count - textured
        if textured == 0 { return "All smooth weaves, so it reads clean and dressy." }
        if smooth == 0 { return "All textured pieces. Try one smooth layer so they don't compete." }
        if textured == 1, let piece = known.first(where: \.fabric.isTextured) {
            return "The \(piece.fabric.label.lowercased()) \(piece.category.singular.lowercased()) is the one textured note against smooth pieces. A nice focal point."
        }
        return "\(smooth) smooth and \(textured) textured pieces, a balanced mix."
    }

    static func color(for items: [ClothingItem]) -> String? {
        guard items.count >= 2 else { return nil }
        let families = items.map(\.colorFamily)
        let accents = items.filter { $0.colorFamily != .neutral && $0.colorFamily != .dark }
        let distinct = Set(accents.map(\.colorFamily))
        if accents.isEmpty { return "All neutrals and darks: easy to wear, and any accessory can bring the color." }
        if accents.count == 1 { return "Neutrals with one accent, the \(accents[0].displayColorName.lowercased())." }
        if distinct.count == 1 { return "Tonal \(distinct.first!.label.lowercased()), anchored by \(families.count - accents.count) neutral \(families.count - accents.count == 1 ? "piece" : "pieces")." }
        return "\(distinct.count) color families together. Keep the rest quiet so they don't fight."
    }
}

struct ThisLookPanel: View {
    let items: [ClothingItem]
    @Binding var name: String
    @Binding var occasion: Occasion
    let match: Outfit?
    let justSaved: Bool
    let onSave: () -> Void

    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This look").font(Typeface.display(21))

            // Palette with each piece's texture.
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Rectangle()
                        .fill(Color(hex: item.colorHex))
                        .overlay { FabricTexture(fabric: item.fabric, baseHex: item.colorHex, scale: 1.1) }
                        .transition(.opacity)
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.08)) }
            .animation(Motion.lift, value: items.map(\.id))
            .accessibilityLabel("Palette: " + items.map(\.displayColorName).joined(separator: ", "))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        FabricSwatch(hex: item.colorHex, fabric: item.fabric, size: 12, corner: 3)
                        Text(item.displayColorName).font(.system(size: 12.5, weight: .medium))
                        Text(item.fabric == .unknown ? item.category.singular : item.fabric.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                note("Texture mix", OutfitNotes.texture(for: items))
                if let colorNote = OutfitNotes.color(for: items) { note("Color", colorNote) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)

            if let match {
                savedState(match)
            } else {
                saveForm
            }
        }
        .padding(22)
        .padding(.top, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel.ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1).ignoresSafeArea() }
    }

    private func note(_ title: String, _ body: String) -> some View {
        (Text(title + ": ").fontWeight(.semibold) + Text(body).foregroundColor(Theme.inkSecondary))
            .font(.system(size: 12.5))
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    private var saveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Name").font(.system(size: 12, weight: .semibold))
                TextField("Saturday market", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSave)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Occasion").font(.system(size: 12, weight: .semibold))
                FlowLayout(spacing: 6) {
                    ForEach(Occasion.allCases) { o in
                        ChipToggle(label: o.label, isOn: occasion == o) { occasion = o }
                    }
                }
            }
            Button(action: onSave) {
                Label("Save to lookbook", systemImage: "bookmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(items.isEmpty)
        }
    }

    private func savedState(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text(justSaved ? "Saved to your lookbook" : "In your lookbook as \(outfit.name)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .scaleEffect(justSaved ? 1 : 0.98)
            .transition(.scale(scale: 0.92).combined(with: .opacity))

            HStack(spacing: 8) {
                if outfit.wasWorn(on: .now) {
                    Label("Today's look", systemImage: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.green)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.greenTonal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Button {
                        withAnimation(Motion.lift) { store.markWorn(outfit) }
                    } label: {
                        Label("Worn today", systemImage: "sun.max").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                }
                Button("Lookbook") { nav.section = .lookbook }
                    .buttonStyle(.quiet)
            }
        }
    }
}

/// Wraps children onto new lines when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        var y: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                y += row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
