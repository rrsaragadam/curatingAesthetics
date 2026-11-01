import Foundation

/// The hook for a future stylist (for example one backed by Claude).
///
/// Nothing calls a real stylist yet. When you add one, implement this protocol,
/// return it from `StylistProvider.current`, and the sidebar card plus the
/// builder's "This look" panel are the places to surface its answers.
protocol Stylist {
    /// Short, specific feedback on a combination ("swap the loafers for the
    /// sneakers to match the canvas jacket").
    func critique(outfit: [ClothingItem], occasion: Occasion) async throws -> String

    /// Pieces that would unlock the most new outfits from what you already own.
    func gaps(in closet: [ClothingItem], outfits: [Outfit]) async throws -> [String]
}

enum StylistProvider {
    /// Nil until a stylist is configured.
    static var current: Stylist? { nil }
}
