import Foundation
import TSCBasic

// A enum containing information about third party dependency.
public enum ThirdPartyDependency: Hashable, Equatable, Codable {
    /// A dependency that represents a pre-compiled .xcframework.
    case xcframework(name: String, path: AbsolutePath, architectures: Set<BinaryArchitecture>)
}

extension ThirdPartyDependency {
    /// The name of the third party dependency.
    public var name: String {
        switch self {
        case let .xcframework(name, _, _):
            return name
        }
    }
}

// MARK: - Codable

extension ThirdPartyDependency {
    private enum Kind: String, Codable {
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case path
        case architectures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .xcframework:
            let name = try container.decode(String.self, forKey: .name)
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let architectures = try container.decode(Set<BinaryArchitecture>.self, forKey: .architectures)
            self = .xcframework(name: name, path: path, architectures: architectures)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .xcframework(name, path, architectures):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }
}
