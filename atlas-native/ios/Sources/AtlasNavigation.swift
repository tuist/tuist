import Foundation
import SwiftUI

/// A read-only navigation intent, never an API path, permission, or server switch.
struct AtlasDestination: Equatable, Hashable {
    let screen: String
    let recordID: String?
    let server: String

    init?(screen: String, recordID: String? = nil, server: URL) {
        guard let capability = AtlasCore.destinations()[screen],
              recordID == nil || capability,
              recordID.map(Self.validRecordID) ?? true,
              let origin = Self.origin(server.absoluteString) else { return nil }
        self.screen = screen
        self.recordID = recordID
        self.server = origin
    }

    init?(url: URL) {
        if url.scheme?.lowercased() == "https" {
            self.init(webURL: url)
            return
        }
        guard url.absoluteString.utf8.count <= 2048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "dev.tuist.atlas",
              components.host?.lowercased() == "navigate",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil, !components.percentEncodedPath.contains("%"),
              components.percentEncodedQuery?.hasPrefix("server=") == true,
              let query = components.queryItems, query.count == 1, query[0].name == "server",
              let address = query[0].value, Self.origin(address) != nil,
              let server = URL(string: address) else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, parts[0].isEmpty else { return nil }
        self.init(screen: String(parts[1]), recordID: parts.count == 3 ? String(parts[2]) : nil, server: server)
    }

    private init?(webURL: URL) {
        guard webURL.absoluteString.utf8.count <= 2048,
              var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              !components.percentEncodedPath.contains("%"), !components.path.contains("\\") else { return nil }
        let path = components.path
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let server = components.url, Self.origin(server.absoluteString) != nil else { return nil }
        let pages = AtlasCore.destinationPaths()
        if let screen = pages.first(where: { $0.value == path })?.key {
            self.init(screen: screen, server: server)
            return
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 3 || parts.count == 4, parts.first == "", parts[1] == "open" {
            self.init(screen: String(parts[2]), recordID: parts.count == 4 ? String(parts[3]) : nil, server: server)
            return
        }
        for (screen, prefix) in AtlasCore.destinationPaths(records: true) where !prefix.isEmpty {
            if path.hasPrefix(prefix + "/") {
                self.init(screen: screen, recordID: String(path.dropFirst(prefix.count + 1)), server: server)
                return
            }
        }
        return nil
    }

    var webURL: URL {
        URL(string: server + "open/" + screen + (recordID.map { "/" + $0 } ?? ""))!
    }

    // Do not send the browser escape back through an app-only landing route.
    var browserURL: URL {
        let prefix = AtlasCore.destinationPaths(records: true)[screen]!
        let path = recordID.flatMap { !prefix.isEmpty && !prefix.hasPrefix("/open/") ? "\(prefix)/\($0)" : nil }
            ?? AtlasCore.destinationPaths()[screen]!
        return URL(string: server + path.dropFirst())!
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "dev.tuist.atlas"
        components.host = "navigate"
        components.path = "/" + screen + (recordID.map { "/" + $0 } ?? "")
        components.queryItems = [URLQueryItem(name: "server", value: server)]
        return components.url!
    }

    func matches(_ server: URL) -> Bool { Self.origin(server.absoluteString) == self.server }

    private static func validRecordID(_ value: String) -> Bool {
        value.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    private static func origin(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              !value.contains("\\"), !value.contains("%"),
              let components = URLComponents(string: value), components.url != nil,
              components.scheme?.lowercased() == "https", let host = components.encodedHost, !host.isEmpty,
              host.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || "-_.:[]".utf8.contains($0) }),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        let port = components.port ?? 443
        return "https://\(host.lowercased())" + (port == 443 ? "" : ":\(port)") + "/"
    }
}

@MainActor
final class AtlasNavigation: ObservableObject {
    @Published var selection = "orbit"
    @Published private(set) var destination: AtlasDestination?
    @Published private(set) var revision = UUID()
    @Published private(set) var destinations: [String: AtlasDestination] = [:]
    @Published private(set) var revisions: [String: UUID] = [:]
    @Published var message: String?
    private(set) var pending: AtlasDestination?
    @Published private var blockers: [UUID: String] = [:]
    var hasProtectedWork: Bool { !blockers.isEmpty }
    var hasVisibleProtectedWork: Bool { blockers.values.contains(selection) }

    func receive(_ url: URL, server: URL?) {
        // ASWebAuthenticationSession owns this callback, not workspace navigation.
        if url.scheme == "dev.tuist.atlas", url.host == "oauth-callback" { return }
        guard let destination = AtlasDestination(url: url) else {
            message = "This Atlas link is invalid or is not supported by this app."
            return
        }
        open(destination, server: server)
    }

    func open(_ destination: AtlasDestination, server: URL?) {
        pending = destination
        resolve(server: server)
    }

    func resolve(server: URL?) {
        guard let server, let pending else { return }
        self.pending = nil
        guard pending.matches(server) else {
            message = "This link belongs to a different Atlas server. Sign in to that server and open the link again."
            return
        }
        guard blockers.isEmpty else {
            message = "Finish or discard your changes, then open the link again."
            return
        }
        message = nil
        destination = pending
        selection = ["orbit", "accounts", "invoices", "profile"].contains(pending.screen) ? pending.screen : "browse"
        destinations[selection] = pending
        revision = UUID()
        revisions[selection] = revision
    }

    func block(_ id: UUID, active: Bool, tab: String? = nil) {
        if active { blockers[id] = tab ?? selection } else { blockers.removeValue(forKey: id) }
    }

    func reset() {
        pending = nil
        destination = nil
        destinations = [:]
        revisions = [:]
        blockers = [:]
        selection = "orbit"
        message = nil
        revision = UUID()
    }
}

private struct AtlasNavigationKey: EnvironmentKey {
    static let defaultValue: AtlasNavigation? = nil
}

extension EnvironmentValues {
    var atlasNavigation: AtlasNavigation? {
        get { self[AtlasNavigationKey.self] }
        set { self[AtlasNavigationKey.self] = newValue }
    }
}

private struct AtlasNavigationProtection: ViewModifier {
    @Environment(\.atlasNavigation) private var navigation
    let active: Bool

    func body(content: Content) -> some View {
        if let navigation {
            content.modifier(AtlasProtectedNavigation(navigation: navigation, active: active))
        } else { content }
    }
}

private struct AtlasProtectedNavigation: ViewModifier {
    @ObservedObject var navigation: AtlasNavigation
    @State private var id = UUID()
    @State private var tab = ""
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                tab = navigation.selection
                navigation.block(id, active: active, tab: tab)
            }
            .onChange(of: active) { _, active in navigation.block(id, active: active, tab: tab) }
            .onDisappear {
                // A tab switch hides the view without ending its draft or mutation.
                if navigation.selection == tab { navigation.block(id, active: false) }
            }
            .alert("Atlas link", isPresented: Binding(
                get: { active && navigation.selection == tab && navigation.message != nil },
                set: { if !$0 { navigation.message = nil } }
            )) {
                Button("OK") { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
    }
}

extension View {
    // A protected view dismissed while its tab is hidden must first set active to false.
    func protectsAtlasNavigation(_ active: Bool = true) -> some View {
        modifier(AtlasNavigationProtection(active: active))
    }
}
