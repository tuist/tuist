import Foundation

public enum AppRouteError: Error, Equatable {
    case invalidURL
    case differentServer
}

public enum AppRoute: Hashable, Sendable {
    case previews
    case profile
    case preview(account: String, project: String, id: String)

    public init(url: URL, serverURL: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil
        else { throw AppRouteError.invalidURL }

        let path: String
        if components.scheme?.lowercased() == "tuist", components.host?.lowercased() == "app" {
            guard components.port == nil else { throw AppRouteError.invalidURL }
            path = components.percentEncodedPath
            if path == "/previews" || path == "/profile" {
                guard components.query == nil else { throw AppRouteError.invalidURL }
                self = path == "/previews" ? .previews : .profile
                return
            }
            let items = components.queryItems ?? []
            guard components.query == nil || (items.count == 1 && items[0].name == "server" && items[0].value != nil),
                  let targetServer = URL(string: items.first?.value ?? "https://tuist.dev")
            else { throw AppRouteError.invalidURL }
            guard let targetBase = Self.serverBase(targetServer), let currentBase = Self.serverBase(serverURL)
            else { throw AppRouteError.invalidURL }
            guard targetBase == currentBase else { throw AppRouteError.differentServer }
        } else {
            guard components.query == nil,
                  var base = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
                  Self.origin(components) != nil, Self.origin(components) == Self.origin(base)
            else { throw AppRouteError.differentServer }
            while base.percentEncodedPath.hasSuffix("/") {
                base.percentEncodedPath.removeLast()
            }
            let prefix = base.percentEncodedPath + "/"
            guard components.percentEncodedPath.hasPrefix(prefix) else { throw AppRouteError.differentServer }
            path = "/" + components.percentEncodedPath.dropFirst(prefix.count)
        }

        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[3] == "previews",
              let account = Self.segment(String(parts[1])),
              let project = Self.segment(String(parts[2])),
              let id = Self.segment(String(parts[4])), id != "latest"
        else { throw AppRouteError.invalidURL }
        self = .preview(account: account, project: project, id: id)
    }

    public func url(serverURL: URL) -> URL {
        guard case .preview = self else { return handoffURL(serverURL: serverURL) }
        var components = URLComponents(string: Self.serverBase(serverURL)!)!
        components.percentEncodedPath += encodedPath
        return components.url!
    }

    public func handoffURL(serverURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "tuist"
        components.host = "app"
        components.percentEncodedPath = encodedPath
        if case .preview = self {
            components.percentEncodedQuery = "server=" + Self.encode(Self.serverBase(serverURL)!)
        }
        return components.url!
    }

    public static func isWebURL(_ url: URL, serverURL: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base = serverBase(serverURL),
              let baseComponents = URLComponents(string: base),
              origin(components) != nil, origin(components) == origin(baseComponents)
        else { return false }
        let path = baseComponents.percentEncodedPath
        return components.percentEncodedPath == path || components.percentEncodedPath.hasPrefix(path + "/")
    }

    private var encodedPath: String {
        switch self {
        case .previews: return "/previews"
        case .profile: return "/profile"
        case let .preview(account, project, id):
            return "/" + [account, project, "previews", id].map(Self.encode).joined(separator: "/")
        }
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        ))!
    }

    private static func segment(_ encoded: String) -> String? {
        guard let value = encoded.removingPercentEncoding, !value.isEmpty, value != ".", value != "..",
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)
                  .union(CharacterSet(charactersIn: "/\\"))) == nil
        else { return nil }
        return value
    }

    private static func origin(_ components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1 ... 65535).contains($0) }) ?? true
        else { return nil }
        let port = components.port.flatMap { $0 == (scheme == "https" ? 443 : 80) ? nil : $0 }
        return "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    private static func serverBase(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let origin = origin(components), components.query == nil, components.fragment == nil
        else { return nil }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return origin + path
    }
}
