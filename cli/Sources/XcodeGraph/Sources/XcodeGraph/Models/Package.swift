import Path

public enum Package: Equatable, Codable, Sendable {
    case remote(url: String, requirement: Requirement)
    case local(path: AbsolutePath)

    public var identity: String {
        let value = switch self {
        case let .remote(url, _):
            url.split(separator: "/").last.map(String.init) ?? url
        case let .local(path):
            path.basename
        }
        let normalizedValue = value.lowercased()
        return normalizedValue.hasSuffix(".git") ? String(normalizedValue.dropLast(4)) : normalizedValue
    }
}

extension XcodeGraph.Package {
    public var isRemote: Bool {
        switch self {
        case .remote:
            return true
        case .local:
            return false
        }
    }
}
