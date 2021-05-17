import Foundation
import TSCBasic

// A node of the third party dependency graph.
public enum DependenciesGraphDependency: Hashable, Equatable, Codable {
    /// A dependency that represents a pre-compiled .xcframework.
    case xcframework(path: AbsolutePath)
}

// MARK: - Codable

extension DependenciesGraphDependency {
    private enum Kind: String, Codable {
        case xcframework
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .xcframework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .xcframework(path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .xcframework(path):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
