import Foundation
import TSCBasic

// A node of the third party dependency graph.
public enum DependenciesGraphNode: Hashable, Equatable, Codable {
    /// A dependency that represents a pre-compiled .xcframework.
    case xcframework(path: AbsolutePath, architectures: Set<BinaryArchitecture>)
}

// MARK: - Codable

extension DependenciesGraphNode {
    private enum Kind: String, Codable {
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case architectures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .xcframework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let architectures = try container.decode(Set<BinaryArchitecture>.self, forKey: .architectures)
            self = .xcframework(path: path, architectures: architectures)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .xcframework(path, architectures):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(architectures, forKey: .architectures)
        }
    }
}
