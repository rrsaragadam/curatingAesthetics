import AppKit
import SwiftUI

/// Edit everything about a piece. Changes apply when you press Save.
struct ItemEditorSheet: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(AppNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @AppStorage("removeBackground") private var removeBackground = true

    @State private var draft: ClothingItem
    @State private var tagText: String
    @State private var color: Color
    @State private var confirmDelete = false
    @State private var choosingPhoto = false

    init(item: ClothingItem) {
        _draft = State(initialValue: item)
        _tagText = State(initialValue: item.tags.filter { $0 != SampleCloset.tag }.joined(separator: ", "))
        _color = State(initialValue: Color(hex: item.colorHex))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.linen)
                        GarmentView(item: draft).padding(18)
                    }
                    .frame(width: 180, height: 180)
                    Button("Replace photo…") { choosingPhoto = true }
                        .buttonStyle(.quiet)
                }

                Form {
                    TextField("Name", text: $draft.name)
                    Picker("Category", selection: $draft.category) {
                        ForEach(Category.allCases) { Text($0.singular).tag($0) }
                    }
                    TextField("Brand", text: $draft.brand)
                    HStack {
                        ColorPicker("Color", selection: $color, supportsOpacity: false)
                        TextField("Color name", text: $draft.colorName, prompt: Text(ColorNamer.name(forHex: draft.colorHex)))
                            .labelsHidden()
                    }
                    Picker("Texture", selection: $draft.fabric) {
                        ForEach(Fabric.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Material", text: $draft.material, prompt: Text("e.g. 100% merino wool"))
                    TextField("Size", text: $draft.size)
                    TextField("Care", text: $draft.care, prompt: Text("e.g. Hand wash cold, lay flat"))
                    LabeledContent("Seasons") {
                        HStack(spacing: 6) {
                            ForEach(Season.allCases) { season in
                                ChipToggle(label: season.label, isOn: draft.seasons.contains(season)) {
                                    if draft.seasons.contains(season) { draft.seasons.remove(season) }
                                    else { draft.seasons.insert(season) }
                                }
                            }
                        }
                    }
                    Picker("Dress code", selection: $draft.formality) {
                        ForEach(Formality.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Tags", text: $tagText, prompt: Text("Comma separated, e.g. thrifted, travel"))
                    Stepper("Worn \(draft.timesWorn) \(draft.timesWorn == 1 ? "time" : "times")",
                            value: $draft.timesWorn, in: 0...999)
                    Toggle("Favorite", isOn: $draft.favorite)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                .formStyle(.columns)
            }
            .padding(24)

            Divider()
            HStack {
                Button("Delete piece", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.quiet)
                    .foregroundStyle(Theme.clay)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 720)
        .background(Theme.panel)
        .onChange(of: color) { _, new in
            let hex = RGB(nsColor: NSColor(new)).hex
            if hex != draft.colorHex { draft.colorHex = hex }
        }
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if nav.selectedItemID == draft.id { nav.selectedItemID = nil }
                store.delete(draft)
                dismiss()
            }
        } message: {
            Text("It's also removed from any saved outfits.")
        }
        .fileImporter(isPresented: $choosingPhoto, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task {
                // Save edits first so the new photo lands on the current version.
                store.update(applyTags(draft))
                if let current = store.item(id: draft.id) {
                    await store.replacePhoto(of: current, with: url, removeBackground: removeBackground)
                    if let updated = store.item(id: draft.id) { draft.imageFile = updated.imageFile }
                }
            }
        }
    }

    private func applyTags(_ item: ClothingItem) -> ClothingItem {
        var copy = item
        let typed = tagText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let keepsSample = item.tags.contains(SampleCloset.tag)
        var seen = Set<String>()
        copy.tags = (typed + (keepsSample ? [SampleCloset.tag] : [])).filter { seen.insert($0).inserted }
        return copy
    }

    private func save() {
        var final = applyTags(draft)
        final.name = final.name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(final)
        dismiss()
    }
}

extension RGB {
    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}
