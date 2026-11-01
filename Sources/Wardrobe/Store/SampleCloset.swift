import Foundation

/// Illustrated sample pieces and looks for a first run. They carry the
/// `sample` tag so they can be cleared in one go.
enum SampleCloset {
    static let tag = "sample"

    static func make(now: Date = .now) -> (items: [ClothingItem], outfits: [Outfit]) {
        func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 24 * 3600) }

        func piece(_ name: String, _ category: Category, _ hex: String, _ colorName: String,
                   fabric: Fabric, material: String, size: String, seasons: Set<Season>,
                   formality: Formality, worn: Int, lastWorn: Double, favorite: Bool = false,
                   care: String = "") -> ClothingItem {
            var item = ClothingItem(name: name, category: category, colorHex: hex, colorName: colorName,
                                    seasons: seasons, formality: formality, fabric: fabric, material: material,
                                    size: size, care: care, tags: [tag], favorite: favorite, imageFile: nil,
                                    addedAt: daysAgo(200), timesWorn: worn, lastWornAt: daysAgo(lastWorn))
            if category == .shoes { item.shoeType = ShoeType.guess(from: name) ?? .unknown }
            return item
        }

        let oxford = piece("Oxford shirt", .top, "#DCE6F2", "Pale blue", fabric: .oxford, material: "100% cotton",
                           size: "M (15.5)", seasons: [], formality: .smartCasual, worn: 18, lastWorn: 3, favorite: true,
                           care: "Machine wash warm, hang dry")
        let merino = piece("Merino crewneck", .top, "#6E7B5B", "Olive", fabric: .fineKnit, material: "100% merino wool",
                           size: "M", seasons: [.fall, .winter], formality: .smartCasual, worn: 9, lastWorn: 5, favorite: true,
                           care: "Hand wash cold, lay flat")
        let tee = piece("White tee", .top, "#FAFAF7", "White", fabric: .jersey, material: "100% cotton jersey",
                        size: "M", seasons: [.spring, .summer], formality: .casual, worn: 31, lastWorn: 1)
        let linenShirt = piece("Linen shirt", .top, "#E8DCC4", "Sand", fabric: .linen, material: "100% linen",
                               size: "M", seasons: [.summer], formality: .casual, worn: 4, lastWorn: 96)
        let jeans = piece("Straight jeans", .bottom, "#3B4F6E", "Indigo", fabric: .denim, material: "100% cotton, 13 oz",
                          size: "32 × 32", seasons: [], formality: .casual, worn: 40, lastWorn: 1, favorite: true)
        let trousers = piece("Pleated trousers", .bottom, "#B8A88A", "Stone", fabric: .twill, material: "Wool blend",
                             size: "32", seasons: [.spring, .fall], formality: .business, worn: 6, lastWorn: 74)
        let chore = piece("Chore jacket", .outerwear, "#8A5A35", "Tobacco", fabric: .canvas, material: "Cotton canvas",
                          size: "M", seasons: [.spring, .fall], formality: .casual, worn: 12, lastWorn: 2, favorite: true)
        let overcoat = piece("Wool overcoat", .outerwear, "#2E2C2A", "Charcoal", fabric: .melton,
                             material: "80% wool, 20% cashmere", size: "40R", seasons: [.winter], formality: .business,
                             worn: 7, lastWorn: 240, care: "Dry clean only")
        let loafers = piece("Suede loafers", .shoes, "#6B4A33", "Brown", fabric: .suede, material: "Suede, leather sole",
                            size: "US 10", seasons: [.spring, .fall], formality: .smartCasual, worn: 15, lastWorn: 3, favorite: true)
        let sneakers = piece("Canvas sneakers", .shoes, "#F1EEE6", "Off-white", fabric: .canvas, material: "Cotton canvas, rubber",
                             size: "US 10", seasons: [], formality: .casual, worn: 52, lastWorn: 1, favorite: true)
        let tote = piece("Leather tote", .accessory, "#4A3426", "Dark brown", fabric: .pebbledLeather,
                         material: "Full-grain leather", size: "One size", seasons: [], formality: .business, worn: 20, lastWorn: 6)

        let items = [oxford, merino, tee, jeans, trousers, chore, overcoat, loafers, sneakers, tote, linenShirt]

        var cal = Calendar.current
        cal.firstWeekday = 2
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        func thisWeek(_ offset: Int) -> [Date] {
            guard let d = cal.date(byAdding: .day, value: offset, to: weekStart), d <= now else { return [] }
            return [d.addingTimeInterval(9 * 3600)]
        }

        let outfits = [
            Outfit(name: "Saturday market", itemIDs: [chore.id, tee.id, jeans.id, sneakers.id], occasion: .weekend,
                   createdAt: daysAgo(40), rating: 5, wornDates: [daysAgo(30), daysAgo(16)] + thisWeek(0)),
            Outfit(name: "Client lunch", itemIDs: [oxford.id, trousers.id, loafers.id, tote.id], occasion: .work,
                   createdAt: daysAgo(60), rating: 4, wornDates: [daysAgo(74), daysAgo(20)] + thisWeek(1)),
            Outfit(name: "Cold commute", itemIDs: [overcoat.id, merino.id, trousers.id, loafers.id], occasion: .work,
                   createdAt: daysAgo(90), rating: 4, wornDates: [daysAgo(240)] + thisWeek(2)),
            Outfit(name: "Late dinner", itemIDs: [linenShirt.id, jeans.id, loafers.id, tote.id], occasion: .dateNight,
                   createdAt: daysAgo(100), rating: 3, wornDates: [daysAgo(96)]),
            Outfit(name: "Easy Sunday", itemIDs: [chore.id, merino.id, jeans.id, sneakers.id], occasion: .weekend,
                   createdAt: daysAgo(20), rating: 5, wornDates: [daysAgo(8)] + thisWeek(3)),
        ]
        return (items, outfits)
    }
}
