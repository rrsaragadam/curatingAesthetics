import Foundation

/// What a product page told us about a piece.
struct ProductDetails: Equatable {
    var sourceURL: URL
    var name: String = ""
    var brand: String = ""
    var imageURLs: [URL] = []
    var colorWord: String = ""
    var material: String = ""
    var care: String = ""
    var sizes: [String] = []
    var description: String = ""
    var breadcrumbs: String = ""
    /// The value of a "Silhouette:" or "Fit:" line or property, e.g. "Straight".
    var silhouetteLine: String = ""
    var fitLine: String = ""

    var categoryGuess: Category? {
        CategoryGuesser.guess(from: name) ?? CategoryGuesser.guess(from: breadcrumbs) ?? CategoryGuesser.guess(from: description)
    }

    var fabricGuess: Fabric? {
        // The title and material line are the most reliable; the description last.
        Fabric.guess(from: name) ?? Fabric.guess(from: material) ?? Fabric.guess(from: description)
    }

    /// The store's own silhouette comes first, then the title ("Wide Pants"),
    /// the store's fit label, and the description.
    var silhouetteGuess: Silhouette? {
        Silhouette.guess(from: silhouetteLine, labeled: true) ?? Silhouette.guess(from: name)
            ?? Silhouette.guess(from: fitLine, labeled: true) ?? Silhouette.guess(from: description)
    }

    var host: String { Self.host(of: sourceURL) }

    static func host(of url: URL) -> String {
        let h = url.host() ?? url.absoluteString
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    var isEmpty: Bool { name.isEmpty && imageURLs.isEmpty }
}

/// Reads a store's product page. Most shops publish schema.org `Product`
/// JSON-LD for search engines; Open Graph tags and Shopify's product JSON are
/// fallbacks, and the visible text is scanned for composition and care lines.
enum ProductImporter {
    enum Failure: LocalizedError {
        case badURL, blocked(Int), nothingFound, noImage

        var errorDescription: String? {
            switch self {
            case .badURL: return "That doesn't look like a web link."
            case .blocked(let code): return "The store didn't share the page (error \(code)). Try the product's own page, or add a photo instead."
            case .nothingFound: return "Couldn't find product details on that page."
            case .noImage: return "The page had no product photo Wardrobe could download."
            }
        }
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    /// A name from the link alone, for stores that won't share their page:
    /// ".../samba-og-shoes/B75806.html" becomes "Samba OG Shoes".
    static func name(fromLink url: URL) -> String {
        let parts = url.pathComponents.reversed().map { ($0 as NSString).deletingPathExtension }
        // Skip product codes such as "B75806"; take the first part that reads as words.
        let words = parts.first { part in
            let tokens = part.split(whereSeparator: { $0 == "-" || $0 == "_" })
            return tokens.count >= 2 && tokens.filter { $0.allSatisfy(\.isLetter) }.count >= 2
        } ?? ""
        return words.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.count <= 2 ? $0.uppercased() : $0.capitalized }
            .joined(separator: " ")
    }

    /// "adidas.ca" becomes "adidas".
    static func brand(fromHost host: String) -> String {
        host.split(separator: ".").first.map(String.init) ?? ""
    }

    static func normalizedURL(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    // MARK: Fetching

    static func fetchDetails(from url: URL) async throws -> ProductDetails {
        let html = try await fetchText(url)
        var details = parse(html: html, pageURL: url)
        if (details.imageURLs.isEmpty || details.sizes.isEmpty || details.name.isEmpty),
           url.path().contains("/products/"),
           let shopify = try? await fetchShopify(url) {
            details.merge(shopify)
        }
        guard !details.isEmpty else { throw Failure.nothingFound }
        return details
    }

    static func downloadImage(_ url: URL, referer: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.blocked(http.statusCode)
        }
        return data
    }

    private static func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.blocked(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Shopify stores answer `<product url>.json` with the full product record.
    private static func fetchShopify(_ url: URL) async throws -> ProductDetails? {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.query = nil
        comps?.fragment = nil
        guard var base = comps?.url?.absoluteString else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        guard let jsonURL = URL(string: base + ".json") else { return nil }
        let text = try await fetchText(jsonURL)
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let product = root["product"] as? [String: Any] else { return nil }
        var d = ProductDetails(sourceURL: url)
        d.name = (product["title"] as? String) ?? ""
        d.brand = (product["vendor"] as? String) ?? ""
        if let images = product["images"] as? [[String: Any]] {
            d.imageURLs = images.compactMap { ($0["src"] as? String).flatMap { resolve($0, against: url) } }
        }
        if let options = product["options"] as? [[String: Any]] {
            for option in options {
                let name = (option["name"] as? String ?? "").lowercased()
                let values = option["values"] as? [String] ?? []
                if name.contains("size") { d.sizes = values }
                if name.contains("color") || name.contains("colour"), let first = values.first { d.colorWord = first }
            }
        }
        let body = plainText(fromHTML: (product["body_html"] as? String) ?? "")
        d.description = String(body.prefix(600))
        d.material = findComposition(in: body) ?? ""
        d.care = findCare(in: body) ?? ""
        d.silhouetteLine = findLabeled("silhouette", in: body) ?? ""
        d.fitLine = findLabeled("fit", in: body) ?? ""
        return d
    }

    // MARK: Parsing

    static func parse(html: String, pageURL: URL) -> ProductDetails {
        var d = ProductDetails(sourceURL: pageURL)

        // 1. JSON-LD
        for block in jsonLDBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            for product in findProducts(in: json) {
                d.merge(details(fromLD: product, pageURL: pageURL))
            }
            if d.breadcrumbs.isEmpty, let crumbs = findBreadcrumbs(in: json) { d.breadcrumbs = crumbs }
        }

        // 2. Open Graph / product meta tags
        let meta = metaTags(in: html)
        if d.name.isEmpty { d.name = meta["og:title"] ?? meta["twitter:title"] ?? titleTag(in: html) ?? "" }
        if d.brand.isEmpty { d.brand = meta["product:brand"] ?? meta["og:brand"] ?? "" }
        if d.colorWord.isEmpty { d.colorWord = meta["product:color"] ?? "" }
        if d.imageURLs.isEmpty {
            d.imageURLs = [meta["og:image:secure_url"], meta["og:image"], meta["twitter:image"]]
                .compactMap { $0 }.compactMap { resolve($0, against: pageURL) }
        }
        if d.description.isEmpty { d.description = meta["og:description"] ?? meta["description"] ?? "" }

        // 3. Visible text for composition and care, which shops rarely put in JSON-LD.
        let text = plainText(fromHTML: html)
        if d.material.isEmpty { d.material = findComposition(in: text) ?? "" }
        if d.care.isEmpty { d.care = findCare(in: text) ?? "" }
        // A store's silhouette filter value (Uniqlo: "groupName":"Silhouette" … "tagName":"Barrel")
        // is kept more carefully than its prose, so it wins.
        if let tagged = silhouetteTag(in: html) { d.silhouetteLine = tagged }
        if d.silhouetteLine.isEmpty { d.silhouetteLine = findLabeled("silhouette", in: text) ?? "" }
        // The color picked in the link beats the page's default color.
        if let picked = colorName(forCodesIn: pageURL, html: html) { d.colorWord = picked }
        if d.colorWord.isEmpty, let shown = findLabeled("colou?r", in: text) { d.colorWord = cleanColorWord(shown) }
        if d.fitLine.isEmpty { d.fitLine = findLabeled("fit", in: text) ?? "" }

        d.name = cleanTitle(d.name, brand: d.brand, host: d.host)
        d.sizes = orderedSizes(d.sizes)
        d.imageURLs = dedupe(d.imageURLs + relatedImages(in: html, to: d.imageURLs, pageURL: pageURL))
        return d
    }

    private static func details(fromLD p: [String: Any], pageURL: URL) -> ProductDetails {
        var d = ProductDetails(sourceURL: pageURL)
        d.name = decodeEntities(p["name"] as? String ?? "")
        if let brand = p["brand"] as? [String: Any] { d.brand = brand["name"] as? String ?? "" }
        else if let brand = p["brand"] as? String { d.brand = brand }
        else if let brands = p["brand"] as? [[String: Any]] { d.brand = brands.first?["name"] as? String ?? "" }
        d.brand = decodeEntities(d.brand)
        d.imageURLs = imageStrings(p["image"]).compactMap { resolve($0, against: pageURL) }
        d.colorWord = stringValue(p["color"]) ?? ""
        d.material = stringValue(p["material"]) ?? ""
        d.description = decodeEntities(stringValue(p["description"]) ?? "")
        if let size = stringValue(p["size"]) { d.sizes = [size] }

        if let props = p["additionalProperty"] as? [[String: Any]] {
            for prop in props {
                let name = (prop["name"] as? String ?? "").lowercased()
                guard let value = stringValue(prop["value"]) else { continue }
                if name.contains("material") || name.contains("composition") || name.contains("fabric") {
                    if d.material.isEmpty { d.material = value }
                } else if name.contains("care") {
                    if d.care.isEmpty { d.care = value }
                } else if name.contains("silhouette") || name == "cut" {
                    if d.silhouetteLine.isEmpty { d.silhouetteLine = value }
                } else if name.contains("fit") {
                    if d.fitLine.isEmpty { d.fitLine = value }
                } else if name.contains("color") || name.contains("colour") {
                    if d.colorWord.isEmpty { d.colorWord = value }
                }
            }
        }

        // ProductGroup variants carry the sizes (and often images).
        if let variants = p["hasVariant"] as? [[String: Any]] {
            for v in variants {
                if let s = stringValue(v["size"]) { d.sizes.append(s) }
                if d.colorWord.isEmpty, let c = stringValue(v["color"]) { d.colorWord = c }
                if d.material.isEmpty, let m = stringValue(v["material"]) { d.material = m }
                if d.imageURLs.isEmpty { d.imageURLs = imageStrings(v["image"]).compactMap { resolve($0, against: pageURL) } }
            }
        }
        return d
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isType(_ obj: [String: Any], _ names: [String]) -> Bool {
        let types: [String]
        if let t = obj["@type"] as? String { types = [t] }
        else if let t = obj["@type"] as? [String] { types = t }
        else { return false }
        return types.contains { t in names.contains { t.caseInsensitiveCompare($0) == .orderedSame || t.hasSuffix("/" + $0) } }
    }

    private static func findProducts(in json: Any) -> [[String: Any]] {
        if let arr = json as? [Any] { return arr.flatMap { findProducts(in: $0) } }
        guard let obj = json as? [String: Any] else { return [] }
        if isType(obj, ["Product", "ProductGroup", "IndividualProduct", "ProductModel"]) { return [obj] }
        var found: [[String: Any]] = []
        for key in ["@graph", "mainEntity", "itemListElement", "item", "offers"] {
            if let value = obj[key] { found += findProducts(in: value) }
        }
        return found
    }

    private static func findBreadcrumbs(in json: Any) -> String? {
        if let arr = json as? [Any] { return arr.lazy.compactMap { findBreadcrumbs(in: $0) }.first }
        guard let obj = json as? [String: Any] else { return nil }
        if isType(obj, ["BreadcrumbList"]), let items = obj["itemListElement"] as? [[String: Any]] {
            let names = items.compactMap { ($0["name"] as? String) ?? (($0["item"] as? [String: Any])?["name"] as? String) }
            return names.joined(separator: " ")
        }
        if let graph = obj["@graph"] { return findBreadcrumbs(in: graph) }
        return nil
    }

    private static func imageStrings(_ value: Any?) -> [String] {
        switch value {
        case let s as String: return [s]
        case let arr as [Any]: return arr.flatMap { imageStrings($0) }
        case let obj as [String: Any]:
            return [obj["url"], obj["contentUrl"]].compactMap { $0 as? String }
        default: return []
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber: return n.stringValue
        case let arr as [Any]:
            let parts = arr.compactMap { stringValue($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        case let obj as [String: Any]: return stringValue(obj["name"] ?? obj["value"])
        default: return nil
        }
    }

    private static func metaTags(in html: String) -> [String: String] {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<meta\s[^>]*>"#, options: .caseInsensitive),
              let attrRegex = try? NSRegularExpression(pattern: #"([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
        else { return [:] }
        let ns = html as NSString
        var result: [String: String] = [:]
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let tns = tag as NSString
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: tag, range: NSRange(location: 0, length: tns.length)) {
                let key = tns.substring(with: a.range(at: 1)).lowercased()
                let r = a.range(at: 2).location != NSNotFound ? a.range(at: 2) : a.range(at: 3)
                attrs[key] = tns.substring(with: r)
            }
            guard let key = (attrs["property"] ?? attrs["name"] ?? attrs["itemprop"])?.lowercased(),
                  let content = attrs["content"], !content.isEmpty, result[key] == nil else { continue }
            result[key] = decodeEntities(content)
        }
        return result
    }

    private static func titleTag(in html: String) -> String? {
        guard let r = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let raw = String(html[r]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Text scanning

    static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg"] {
            s = s.replacingOccurrences(of: "(?s)<\(tag)[^>]*>.*?</\(tag)>", with: " ",
                                       options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>|</div>", with: ". ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s
    }

    /// "100% cotton", "80% wool, 20% cashmere", "Shell: 100% nylon".
    static func findComposition(in text: String) -> String? {
        let fibre = "[A-Za-zé]+(?: [A-Za-zé]+)?"
        let pattern = "\\d{1,3}(?:[.,]\\d)?\\s?%\\s?\(fibre)(?:\\s?[,/&]\\s?\\d{1,3}(?:[.,]\\d)?\\s?%\\s?\(fibre)){0,4}"
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        var found = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop trailing words that aren't fibres ("100% cotton Made in Portugal").
        let stop = [" made", " imported", " machine", " hand", " care", " fit", " model", " and"]
        for word in stop {
            if let range = found.range(of: word, options: [.caseInsensitive, .backwards]),
               range.upperBound == found.endIndex { found.removeSubrange(range) }
        }
        return found.prefix(1).uppercased() + found.dropFirst()
    }

    /// The value after a label such as "Silhouette: Straight" or "Fit - Relaxed".
    static func findLabeled(_ label: String, in text: String) -> String? {
        let pattern = "(?i)\\b\(label)\\s*[:\\-–]\\s*([A-Za-z][A-Za-z -]{1,24}?)(?=[.,;|<]|\\s-|\\s{2}|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    /// The silhouette a store tags the product with in its page data.
    static func silhouetteTag(in html: String) -> String? {
        let pattern = #"(?i)"(?:groupName|name|label|attribute)"\s*:\s*"silhouette"[^{}]{0,80}?"(?:tagName|value|displayValue)"\s*:\s*"([^"]{2,24})""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// The name a store gives the color code in the link, from its page data:
    /// `"displayCode":"66","name":"BLUE"` for "?colorDisplayCode=66".
    static func colorName(forCodesIn pageURL: URL, html: String) -> String? {
        for code in colorCodes(in: pageURL) {
            let escaped = NSRegularExpression.escapedPattern(for: code)
            let pattern = #"(?i)"[a-z]*code"\s*:\s*"(?:col)?"# + escaped + #""\s*,\s*"name"\s*:\s*"([^"]{2,30})""#
            if let r = html.range(of: pattern, options: .regularExpression),
               let name = String(html[r]).components(separatedBy: "\"").dropLast().last {
                return cleanColorWord(name)
            }
        }
        return nil
    }

    /// "66 BLUE" becomes "Blue", "NAVY" becomes "Navy".
    static func cleanColorWord(_ word: String) -> String {
        let trimmed = word.replacingOccurrences(of: #"^\d+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    static func findCare(in text: String) -> String? {
        let pattern = "(?i)(machine wash|hand wash|dry clean|wash cold|cold wash|do not wash|spot clean|wash at \\d+)[^.;|]{0,70}"
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        let found = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return found.prefix(1).uppercased() + found.dropFirst()
    }

    // MARK: Cleanup

    static func cleanTitle(_ title: String, brand: String, host: String) -> String {
        var t = decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
        // "Waffle Henley | Brand" or "Waffle Henley – Brand"
        for sep in [" | ", " – ", " — ", " - "] {
            if let r = t.range(of: sep, options: .backwards) {
                let tail = t[r.upperBound...].lowercased()
                let brandLower = brand.lowercased()
                let hostStem = host.split(separator: ".").first.map { String($0).lowercased() } ?? ""
                if (!brandLower.isEmpty && tail.contains(brandLower)) || (!hostStem.isEmpty && tail.replacingOccurrences(of: " ", with: "").contains(hostStem)) {
                    t = String(t[..<r.lowerBound])
                }
            }
        }
        if !brand.isEmpty, t.lowercased().hasPrefix(brand.lowercased() + " ") {
            t = String(t.dropFirst(brand.count + 1))
        }
        // Many shops shout titles in capitals.
        if t == t.uppercased() && t.count > 3 { t = t.lowercased().capitalizedFirst }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let sizeOrder = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "XXXL", "3XL"]

    static func orderedSizes(_ sizes: [String]) -> [String] {
        var seen = Set<String>()
        let unique = sizes.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count <= 14 && seen.insert($0.lowercased()).inserted }
        let allLetter = unique.allSatisfy { sizeOrder.contains($0.uppercased()) }
        if allLetter {
            return unique.sorted { sizeOrder.firstIndex(of: $0.uppercased())! < sizeOrder.firstIndex(of: $1.uppercased())! }
        }
        return unique
    }

    /// Drops repeats, treating resized copies ("photo.jpg?width=600") as the same photo.
    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.query = nil
            return seen.insert(comps?.string ?? url.absoluteString).inserted
        }
    }

    // MARK: Photos

    /// Other photos of the same product on the page. Stores often only tag one
    /// photo (usually a model shot) in their metadata while the gallery, flat
    /// lays included, sits in the page's data. They share the product number
    /// in their file names, which is how they're found here.
    static func relatedImages(in html: String, to known: [URL], pageURL: URL) -> [URL] {
        guard let productID = known.lazy.compactMap({ productNumber(in: $0.lastPathComponent) }).first else { return [] }
        let unescaped = html.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u002F", with: "/")
        let pattern = #"(?:https?:)?//[^"'\s<>()]+?\.(?:jpe?g|png|webp|avif)(?:\?[^"'\s<>()]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = unescaped as NSString
        let skip = ["chip", "swatch", "thumb", "icon", "logo", "sprite", "badge", "banner", "navi", "feature"]
        return regex.matches(in: unescaped, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range)
            let file = raw.lowercased()
            guard file.contains(productID), !skip.contains(where: { file.contains($0) }) else { return nil }
            return resolve(raw, against: pageURL)
        }
    }

    /// The longest run of five or more digits in a file name, e.g. "471809".
    private static func productNumber(in fileName: String) -> String? {
        let runs = fileName.split(whereSeparator: { !$0.isNumber }).filter { $0.count >= 5 }
        return runs.max(by: { $0.count < $1.count }).map { String($0) }
    }

    /// The short codes in a link's query that can name a color, e.g. "09" in
    /// "?colorDisplayCode=09".
    static func colorCodes(in pageURL: URL) -> [String] {
        (URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .compactMap(\.value).filter { (1...6).contains($0.count) && $0.allSatisfy { $0.isLetter || $0.isNumber } }
            .map { $0.lowercased() }
    }

    /// Whether a photo's file name carries one of the link's color codes
    /// ("goods_09_471809.jpg" for "?colorDisplayCode=09").
    static func photo(_ url: URL, matchesColorIn pageURL: URL) -> Bool {
        let codes = colorCodes(in: pageURL)
        let tokens = url.lastPathComponent.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return codes.contains { code in tokens.contains { $0 == code } }
    }

    /// Photos in the order worth trying: those in the link's color first, then
    /// photos that don't name a color. A photo named like one in the link's
    /// color but with another code in that spot ("goods_19_471809.jpg" next to
    /// "cagoods_09_471809.jpg") shows another color, so it's left out.
    static func photoOrder(_ urls: [URL], pageURL: URL) -> [URL] {
        let codes = colorCodes(in: pageURL)
        func tokens(_ url: URL) -> [String] {
            url.lastPathComponent.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        let matching = urls.filter { photo($0, matchesColorIn: pageURL) }
        // Each photo in the link's color, with the position of its color code.
        let templates: [(tokens: [String], at: Int)] = matching.compactMap { url in
            let t = tokens(url)
            return t.firstIndex(where: { codes.contains($0) }).map { (t, $0) }
        }
        func isOtherColor(_ url: URL) -> Bool {
            let t = tokens(url)
            return templates.contains { template in
                guard t.count == template.tokens.count, t[template.at] != template.tokens[template.at],
                      t[template.at].count == template.tokens[template.at].count else { return false }
                let otherDifferences = zip(t, template.tokens).enumerated()
                    .filter { $0.offset != template.at && $0.element.0 != $0.element.1 }.count
                return otherDifferences <= 1
            }
        }
        return matching + urls.filter { !photo($0, matchesColorIn: pageURL) && !isOtherColor($0) }
    }

    static func resolve(_ string: String, against base: URL) -> URL? {
        let s = decodeEntities(string).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("data:") else { return nil }
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        return URL(string: s, relativeTo: base)?.absoluteURL
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">",
                     "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&rsquo;": "’", "&lsquo;": "‘",
                     "&rdquo;": "”", "&ldquo;": "“", "&eacute;": "é", "&reg;": "®", "&trade;": "™"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities: &#8217; and &#x2019;
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            let digits = ns.substring(with: m.range(at: 2))
            if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}

private extension ProductDetails {
    /// Fills empty fields from another source without overwriting what we have.
    mutating func merge(_ other: ProductDetails) {
        if name.isEmpty { name = other.name }
        if brand.isEmpty { brand = other.brand }
        if imageURLs.isEmpty { imageURLs = other.imageURLs }
        if colorWord.isEmpty { colorWord = other.colorWord }
        if material.isEmpty { material = other.material }
        if care.isEmpty { care = other.care }
        if description.isEmpty { description = other.description }
        if breadcrumbs.isEmpty { breadcrumbs = other.breadcrumbs }
        if silhouetteLine.isEmpty { silhouetteLine = other.silhouetteLine }
        if fitLine.isEmpty { fitLine = other.fitLine }
        sizes += other.sizes
    }
}

enum CategoryGuesser {
    static func guess(from text: String) -> Category? {
        let t = text.lowercased()
        let rules: [(Category, [String])] = [
            (.shoes, ["sneaker", "trainer", "loafer", "boot", "shoe", "sandal", "derby", "oxford shoe", "mule", "heel", "espadrille", "slipper"]),
            (.dress, ["dress", "jumpsuit", "romper", "overall", "gown"]),
            (.jacket, ["jacket", "blazer", "overshirt", "shacket", "chore", "bomber", "trucker", "harrington", "windbreaker", "sport coat"]),
            (.outerwear, ["coat", "parka", "anorak", "trench", "puffer", "gilet", "vest"]),
            (.bottom, ["jean", "trouser", "pants", "chino", "shorts", "skirt", "legging", "jogger"]),
            (.accessory, ["bag", "tote", "belt", "scarf", "hat", "beanie", "cap", "sock", "wallet", "sunglass", "glove", "tie", "watch", "necklace", "ring", "bracelet"]),
            (.top, ["shirt", "tee", "t-shirt", "henley", "polo", "sweater", "crewneck", "cardigan", "hoodie", "sweatshirt", "blouse", " top", "tank", "knit", "jumper", "turtleneck"]),
        ]
        // Earliest mention wins, so "shirt jacket" is outerwear only if "jacket" comes first.
        var best: (Category, String.Index)?
        for (category, words) in rules {
            for w in words {
                if let r = t.range(of: w), best == nil || r.lowerBound < best!.1 {
                    best = (category, r.lowerBound)
                }
            }
        }
        return best?.0
    }
}
