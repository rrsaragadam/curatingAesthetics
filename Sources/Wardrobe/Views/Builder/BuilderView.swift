import SwiftUI

/// The slots an outfit is built from, top to bottom of the list.
enum BuilderSlot: String, CaseIterable, Identifiable {
    case outerwear, top, bottom, shoes, accessory
    var id: String { rawValue }

    var label: String {
        switch self {
        case .outerwear: return "Jacket or coat"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .shoes: return "Shoes"
        case .accessory: return "Accessory"
        }
    }

    var isOptional: Bool { self == .outerwear || self == .accessory }

    static func slot(for category: Category) -> BuilderSlot {
        switch category {
        case .jacket, .outerwear: return .outerwear
        case .top, .dress: return .top
        case .bottom: return .bottom
        case .shoes: return .shoes
        case .accessory: return .accessory
        }
    }
}

struct BuilderView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var picks: [BuilderSlot: UUID] = [:]
    @State private var locked: Set<BuilderSlot> = []
    @State private var name = ""
    @State private var occasion: Occasion = .everyday
    @State private var justSaved: UUID?
    @State private var didSetUp = false
    /// The stylist's last word, kept while the builder still shows those pieces.
    @State private var stylistNote: (itemIDs: Set<UUID>, title: String, text: String, isLook: Bool)?
    @State private var isStyling = false
    private let stylist = StylistProvider.current

    // MARK: Options

    private func options(for slot: BuilderSlot) -> [ClothingItem?] {
        let pieces: [ClothingItem]
        switch slot {
        case .top: pieces = store.items.filter { $0.category == .top || $0.category == .dress }
        default: pieces = store.items.filter { BuilderSlot.slot(for: $0.category) == slot }
        }
        let sorted = pieces.sorted { $0.addedAt < $1.addedAt }
        let optional = slot.isOptional || (slot == .bottom && wearingDress)
        return optional ? sorted.map(Optional.some) + [nil] : sorted.map(Optional.some)
    }

    private var wearingDress: Bool {
        picks[.top].flatMap { store.item(id: $0) }?.category == .dress
    }

    private var activeSlots: [BuilderSlot] {
        BuilderSlot.allCases.filter { slot in
            !(options(for: slot).compactMap { $0 }.isEmpty)
        }
    }

    private func current(_ slot: BuilderSlot) -> ClothingItem? {
        if slot == .bottom && wearingDress && picks[.bottom] == nil { return nil }
        return picks[slot].flatMap { store.item(id: $0) }
    }

    private var currentItems: [ClothingItem] {
        BuilderSlot.allCases.compactMap { current($0) }
    }

    private var match: Outfit? { store.outfit(matching: Set(currentItems.map(\.id))) }

    // MARK: Body

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 12) {
                                OutfitStage(pieces: stagePieces)
                                matchNote
                            }
                            // The stage gives up width first so the slot rows keep
                            // room for their labels on smaller windows.
                            .frame(minWidth: 220, maxWidth: 350)
                            slotList
                                .frame(minWidth: 330)
                                .layoutPriority(1)
                        }
                    }
                    .padding(30)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    ThisLookPanel(items: currentItems, name: $name, occasion: $occasion,
                                  match: match, justSaved: justSaved == match?.id && match != nil,
                                  stylistNote: currentStylistNote, isStylistBusy: isStyling,
                                  onAskStylist: stylist == nil ? nil : critique,
                                  onDeclineLook: stylistNote?.isLook == true && currentStylistNote != nil ? declineLook : nil,
                                  onSave: save)
                        .frame(width: 320)
                }
            }
        }
        .onAppear(perform: setUp)
        .onChange(of: nav.pieceToStyle) { setUp() }
        .onChange(of: nav.outfitToEdit) { setUp() }
        .onChange(of: nav.stylistRequest) { setUp() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Outfit builder").font(.wardrobeTitle)
                Text("Flip through each slot, lock what you love, shuffle the rest.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.top, 30)
            Spacer()
            if stylist != nil {
                Button(action: styleMe) {
                    Label(isStyling ? "Styling…" : "Style me", systemImage: "sparkles")
                }
                .buttonStyle(.quiet)
                .disabled(isStyling)
                .keyboardShortcut("y", modifiers: .command)
                .help("Ask the on-device stylist for a \(occasion.label.lowercased()) look around your locked pieces (⌘Y)")
                .padding(.top, 30)
            }
            Button(action: shuffle) {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Shuffle unlocked")
                    Text("\(activeSlots.filter { !locked.contains($0) }.count)")
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.dark)
            .keyboardShortcut("r", modifiers: .command)
            .help("Shuffle every unlocked slot (⌘R)")
            .padding(.top, 30)
        }
    }

    private var matchNote: some View {
        HStack(spacing: 10) {
            Image(systemName: match != nil ? "bookmark.fill" : "sparkle")
                .foregroundStyle(Theme.green)
                .frame(width: 28, height: 28)
                .background(Theme.greenTonal, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                if let match {
                    Text("You've saved this as \(match.name)").font(.system(size: 12.5, weight: .semibold))
                    Text(match.timesWorn == 0 ? "Not worn yet" : "Worn \(match.timesWorn) \(match.timesWorn == 1 ? "time" : "times")")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("A new combination").font(.system(size: 12.5, weight: .semibold))
                    Text("\(currentItems.count) \(currentItems.count == 1 ? "piece" : "pieces"), never worn together")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line) }
        .animation(Motion.lift, value: match?.id)
    }

    private var slotList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(activeSlots) { slot in
                    let opts = options(for: slot)
                    let item = current(slot)
                    let index = opts.firstIndex { $0?.id == item?.id } ?? 0
                    SlotRow(slot: slot, item: item, position: "\(index + 1) of \(opts.count)",
                            isLocked: locked.contains(slot),
                            onToggleLock: { toggleLock(slot) },
                            onPrevious: { step(slot, by: -1) },
                            onNext: { step(slot, by: 1) })
                }
                Text("Pieces from your closet appear in their slot automatically. Accessories, jackets and coats can be left off.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: 460)
    }

    private var stagePieces: [StagePiece] {
        let hasCoat = current(.outerwear) != nil
        return StageLayout.drawOrder.compactMap { slot -> StagePiece? in
            guard let item = current(slot) else { return nil }
            let frame = StageLayout.frame(for: slot, item: item, hasCoat: hasCoat)
            return StagePiece(slot: slot, item: item, frame: frame)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.green)
            Text("Add a few pieces first").font(Typeface.display(24))
            Text("Once your closet has a top, a bottom and some shoes, you can flip through combinations here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Go to closet") { nav.section = .closet }.buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func animate(_ body: () -> Void) {
        withAnimation(Motion.respecting(reduceMotion, .spring(response: 0.48, dampingFraction: 0.62)), body)
    }

    private func setUp() {
        if nav.stylistRequest != nil {
            nav.stylistRequest = nil
            styleMe()
            return
        }
        if let outfitID = nav.outfitToEdit, let outfit = store.outfits.first(where: { $0.id == outfitID }) {
            nav.outfitToEdit = nil
            animate {
                picks = [:]
                for item in store.items(of: outfit) { picks[BuilderSlot.slot(for: item.category)] = item.id }
                locked = Set(picks.keys)
                name = outfit.name
                occasion = outfit.occasion
            }
            return
        }
        if let pieceID = nav.pieceToStyle, let piece = store.item(id: pieceID) {
            nav.pieceToStyle = nil
            let slot = BuilderSlot.slot(for: piece.category)
            animate {
                picks[slot] = piece.id
                locked = [slot]
                name = ""
            }
            shuffle()
            return
        }
        // Drop picks for pieces that were deleted since last time.
        picks = picks.filter { store.item(id: $0.value) != nil }
        if !didSetUp && picks.isEmpty { shuffle() }
        didSetUp = true
    }

    private func shuffle() {
        animate {
            for slot in BuilderSlot.allCases where !locked.contains(slot) {
                let opts = options(for: slot)
                guard !opts.isEmpty else { picks[slot] = nil; continue }
                // Optional slots are left off a third of the time.
                let pool: [ClothingItem?] = slot.isOptional && opts.count > 1 && Int.random(in: 0..<3) > 0
                    ? opts.filter { $0 != nil } : opts
                let currentID = picks[slot]
                let fresh = pool.filter { $0?.id != currentID }
                picks[slot] = (fresh.randomElement() ?? pool.randomElement() ?? nil)?.id
            }
            // A dress fills the bottom slot too.
            if wearingDress && !locked.contains(.bottom) { picks[.bottom] = nil }
            name = ""
        }
    }

    private func step(_ slot: BuilderSlot, by delta: Int) {
        let opts = options(for: slot)
        guard !opts.isEmpty else { return }
        let index = opts.firstIndex { $0?.id == current(slot)?.id } ?? 0
        let next = (index + delta + opts.count) % opts.count
        animate {
            picks[slot] = opts[next]?.id
            if slot == .top && wearingDress { picks[.bottom] = nil }
        }
    }

    private func toggleLock(_ slot: BuilderSlot) {
        withAnimation(Motion.lift) {
            if locked.contains(slot) { locked.remove(slot) } else { locked.insert(slot) }
        }
    }

    private var currentStylistNote: (title: String, text: String)? {
        guard let note = stylistNote, note.itemIDs == Set(currentItems.map(\.id)) else { return nil }
        return (note.title, note.text)
    }

    /// Fills the unlocked slots with the stylist's pick for the chosen occasion.
    private func styleMe() {
        guard let stylist, !isStyling, !store.items.isEmpty else { return }
        let keeping = locked.compactMap { current($0) }
        isStyling = true
        Task {
            defer { isStyling = false }
            do {
                let looks = try await stylist.suggest(from: store.items, saved: store.outfits, taste: store.taste, occasion: occasion,
                                                      season: .current(), keeping: keeping, count: 1)
                guard let look = looks.first else { return }
                animate {
                    picks = [:]
                    for item in look.itemIDs.compactMap({ store.item(id: $0) }) {
                        picks[BuilderSlot.slot(for: item.category)] = item.id
                    }
                    name = look.name
                }
                stylistNote = (Set(look.itemIDs), "Stylist", look.why, true)
            } catch {
                stylistNote = (Set(currentItems.map(\.id)), "Stylist", "Couldn't put a look together: \(error.localizedDescription)", false)
            }
        }
    }

    /// Remembers that the stylist's look missed, and asks for another.
    private func declineLook(_ reason: DeclineReason) {
        store.decline(look: currentItems.map(\.id), because: reason)
        stylistNote = nil
        styleMe()
    }

    /// Asks the stylist what works about the current look and what to swap.
    private func critique() {
        guard let stylist, !isStyling, !currentItems.isEmpty else { return }
        let items = currentItems
        isStyling = true
        Task {
            defer { isStyling = false }
            let text: String
            do {
                text = try await stylist.critique(outfit: items, occasion: occasion, closet: store.items)
            } catch {
                text = "Couldn't read this look: \(error.localizedDescription)"
            }
            stylistNote = (Set(items.map(\.id)), "Stylist", text, false)
        }
    }

    private func save() {
        guard !currentItems.isEmpty else { return }
        let outfit = store.saveOutfit(name: name, itemIDs: currentItems.map(\.id), occasion: occasion)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { justSaved = outfit.id }
    }
}

// MARK: - Stage

struct StagePiece: Identifiable {
    let slot: BuilderSlot
    let item: ClothingItem
    let frame: StageLayout.Frame
    var id: String { slot.rawValue + item.id.uuidString }
}

/// Where each slot sits on the linen board, in a 350 × 640 coordinate space.
enum StageLayout {
    struct Frame { let x: CGFloat; let y: CGFloat; let size: CGFloat; let angle: Double }

    static let size = CGSize(width: 350, height: 640)
    static let drawOrder: [BuilderSlot] = [.accessory, .shoes, .bottom, .outerwear, .top]

    static func frame(for slot: BuilderSlot, item: ClothingItem, hasCoat: Bool) -> Frame {
        if item.category == .dress {
            return hasCoat ? Frame(x: 128, y: 70, size: 214, angle: 3) : Frame(x: 66, y: 60, size: 240, angle: -2)
        }
        switch slot {
        case .outerwear: return Frame(x: 8, y: 30, size: 196, angle: -6)
        case .top: return hasCoat ? Frame(x: 146, y: 52, size: 186, angle: 4) : Frame(x: 78, y: 36, size: 196, angle: -2)
        case .bottom: return Frame(x: 80, y: 248, size: 200, angle: -2)
        case .shoes: return Frame(x: 20, y: 468, size: 164, angle: -8)
        case .accessory: return Frame(x: 196, y: 474, size: 134, angle: 6)
        }
    }
}

/// The linen board the look is laid out on. New pieces drop in with a little
/// tumble; Reduce Motion turns that into a fade.
struct OutfitStage: View {
    let pieces: [StagePiece]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / StageLayout.size.width, geo.size.height / StageLayout.size.height)
            ZStack(alignment: .topLeading) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                    StagePieceView(piece: piece)
                        .frame(width: piece.frame.size, height: piece.frame.size)
                        .rotationEffect(.degrees(piece.frame.angle))
                        .offset(x: piece.frame.x, y: piece.frame.y)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .modifier(active: Tumble(progress: 0, tilt: index.isMultiple(of: 2) ? -7 : 6),
                                                 identity: Tumble(progress: 1, tilt: 0)),
                            removal: .opacity.combined(with: .scale(scale: 0.92))))
                }
            }
            .frame(width: StageLayout.size.width, height: StageLayout.size.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .aspectRatio(StageLayout.size.width / StageLayout.size.height, contentMode: .fit)
        .frame(maxHeight: 560)
        .background(Theme.linen)
        .overlay(alignment: .bottom) {
            // A soft floor so the shoes have somewhere to stand.
            LinearGradient(colors: [.clear, Theme.linenDeep.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Look preview: " + pieces.map(\.item.name).joined(separator: ", "))
    }
}

private struct Tumble: ViewModifier {
    let progress: Double
    let tilt: Double

    func body(content: Content) -> some View {
        content
            .offset(y: (1 - progress) * -26)
            .rotationEffect(.degrees(tilt * (1 - progress)))
            .opacity(progress)
    }
}

private struct StagePieceView: View {
    let piece: StagePiece
    @State private var hovering = false

    var body: some View {
        GarmentView(item: piece.item)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 8)
            .offset(y: hovering ? -5 : 0)
            .rotationEffect(.degrees(hovering ? -2 : 0))
            .onHover { hovering = $0 }
            .animation(Motion.lift, value: hovering)
            .help(piece.item.name)
    }
}

// MARK: - Slot row

private struct SlotRow: View {
    let slot: BuilderSlot
    let item: ClothingItem?
    let position: String
    let isLocked: Bool
    let onToggleLock: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.linen)
                if let item {
                    GarmentView(item: item)
                        .padding(8)
                        .id(item.id)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Image(systemName: "minus")
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(slot.label) · \(position)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(item?.name ?? "None")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item == nil ? Theme.inkTertiary : Theme.ink)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)

            Button(action: onToggleLock) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isLocked ? Theme.onGreen : Theme.inkSecondary)
                    .background(isLocked ? Theme.green : Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        if !isLocked { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line) }
                    }
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLocked ? "Unlock \(slot.label)" : "Lock \(slot.label)")
            .help(isLocked ? "Locked: shuffle keeps this piece" : "Lock this piece")

            HStack(spacing: 4) {
                Button(action: onPrevious) { Image(systemName: "chevron.left").frame(width: 30, height: 34) }
                    .accessibilityLabel("Previous \(slot.label)")
                Button(action: onNext) { Image(systemName: "chevron.right").frame(width: 30, height: 34) }
                    .accessibilityLabel("Next \(slot.label)")
            }
            .buttonStyle(WardrobeButtonStyle(kind: .quiet, compact: true))
        }
        .padding(10)
        .background(isLocked ? Theme.greenTonal.opacity(0.55) : Theme.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isLocked ? Theme.green.opacity(0.6) : Theme.line, lineWidth: isLocked ? 1.5 : 1)
        }
        .animation(Motion.lift, value: isLocked)
    }
}
