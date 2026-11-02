import SwiftUI

/// The stylist's read of your closet: your style in a sentence, then pieces
/// you don't own that fit it, each drawn in its color with the pieces you'd
/// wear it with.
struct StylistGapsSheet: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case loading, done(StylistGaps), failed(String) }

    @State private var phase: Phase = .loading
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gaps in your closet").font(Typeface.display(24))
                Text("Pieces that fit your style and would make the most new outfits with what you own.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading your closet…").font(.system(size: 12.5)).foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .done(let gaps):
                    results(gaps)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text("Suggested on this Mac from each piece's details.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
                Spacer()
                Button("More ideas", action: load)
                    .buttonStyle(.quiet)
                    .disabled(isLoading)
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 640, height: 600, alignment: .top)
        .background(Theme.ground)
        .onAppear(perform: load)
        .onDisappear { task?.cancel() }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func results(_ gaps: StylistGaps) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !gaps.style.isEmpty {
                    (Text("Your style: ").fontWeight(.semibold) + Text(gaps.style).foregroundColor(Theme.inkSecondary))
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
                ForEach(gaps.pieces) { gap in
                    GapCard(gap: gap)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func load() {
        guard let stylist = StylistProvider.current else {
            phase = .failed(StylistProvider.unavailableReason ?? "The stylist isn't available.")
            return
        }
        guard !store.items.isEmpty else {
            phase = .failed("Add a few pieces to your closet first.")
            return
        }
        phase = .loading
        task?.cancel()
        task = Task {
            do {
                let gaps = try await stylist.gaps(in: store.items, outfits: store.outfits)
                if !Task.isCancelled { withAnimation(Motion.settle) { phase = .done(gaps) } }
            } catch {
                if !Task.isCancelled { phase = .failed("Couldn't read your closet: \(error.localizedDescription)") }
            }
        }
    }
}

private struct GapCard: View {
    @Environment(WardrobeStore.self) private var store
    let gap: StylistGap

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            GarmentIllustration(category: gap.category, hex: gap.colorHex, fabric: gap.fabric)
                .padding(10)
                .frame(width: 84, height: 84)
                .background(Theme.linen, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(gap.name).font(.system(size: 14, weight: .semibold))
                    Text(gap.category.singular)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.greenTonal, in: Capsule())
                        .foregroundStyle(Theme.green)
                }
                if !gap.why.isEmpty {
                    Text(gap.why)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let owned = gap.pairsWith.compactMap { store.item(id: $0) }
                if !owned.isEmpty {
                    FlowLayout(spacing: 6) {
                        Text("Goes with")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                            .padding(.vertical, 3)
                        ForEach(owned) { item in
                            HStack(spacing: 5) {
                                FabricSwatch(hex: item.colorHex, fabric: item.fabric, size: 10, corner: 2.5)
                                Text(item.name).font(.system(size: 11.5)).lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.hover, in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line) }
        .accessibilityElement(children: .combine)
    }
}
