import AppKit
import SwiftUI
import WebKit

/// Where to see real versions of a piece the stylist suggests: Pinterest for
/// how people wear it, and stores for buying it.
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

/// Pinterest results for a suggestion, inside the app. Pinterest asks you to
/// sign in once; the sign-in is kept for next time.
struct PinterestSheet: View {
    let query: String
    @Environment(\.dismiss) private var dismiss
    @State private var webView = WKWebView()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.quiet)
                    .help("Back")
                VStack(alignment: .leading, spacing: 1) {
                    Text(query).font(.system(size: 14, weight: .semibold))
                    Text("On Pinterest").font(.system(size: 11.5)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Button("Open in Browser") {
                    if let url = webView.url ?? ProductSearch.pinterestURL(query) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.quiet)
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            WebPane(webView: webView)
        }
        .frame(width: 960, height: 720)
        .background(Theme.ground)
        .onAppear {
            if let url = ProductSearch.pinterestURL(query) { webView.load(URLRequest(url: url)) }
        }
    }
}

private struct WebPane: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
