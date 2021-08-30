import Foundation

/// A preset build configuration used for convenience
public enum PresetBuildConfiguration: Codable {
    case debug
    case release
    case custom(String)

    var name: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        case let .custom(name): return name
        }
    }

    private enum Kind: String, Codable {
        case debug
        case release
        case custom
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .debug:
            self = .debug
        case .release:
            self = .release
        case .custom:
            let value = try container.decode(String.self, forKey: .value)
            self = .custom(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .debug:
            try container.encode(Kind.debug, forKey: .kind)
        case .release:
            try container.encode(Kind.release, forKey: .kind)
        case let .custom(name):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(name, forKey: .value)
        }
    }
}
