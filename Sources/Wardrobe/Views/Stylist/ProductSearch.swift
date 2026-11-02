import Foundation

/// Where to see real versions of a piece the stylist suggests: Pinterest for
/// how people wear it, and stores for buying it. Both open in your browser,
/// where you're already signed in and your password manager works.
enum ProductSearch {
    /// The suggestion as a search, with "men" or "women" added when the
    /// closet's own product names say which.
    static func query(for gap: StylistGap, closet: [ClothingItem]) -> String {
        let names = closet.map { " " + $0.name.lowercased() + " " }
        let men = names.filter { $0.contains(" men") || $0.contains(" men's") }.count
        let women = names.filter { $0.contains(" women") }.count
        let hint = men > women ? " men" : women > men ? " women" : ""
        return gap.name + hint
    }

    static func pinterestURL(_ query: String) -> URL? {
        url("https://www.pinterest.com/search/pins/", query + " outfit")
    }

    static func shoppingURL(_ query: String) -> URL? {
        url("https://www.google.com/search", query, extra: [URLQueryItem(name: "udm", value: "28")])
    }

    /// A search limited to one store, such as uniqlo.com.
    static func storeURL(_ query: String, host: String) -> URL? {
        url("https://www.google.com/search", "site:\(host) " + query)
    }

    /// Stores the closet's pieces came from, most used first.
    static func stores(in closet: [ClothingItem]) -> [String] {
        let hosts = closet.compactMap(\.sourceHost)
        let counts = Dictionary(hosts.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map(\.key)
    }

    private static func url(_ base: String, _ query: String, extra: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)] + extra
        return components?.url
    }
}
