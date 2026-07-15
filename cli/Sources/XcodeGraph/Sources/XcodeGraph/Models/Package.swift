import Foundation
import Path

public struct Package: Equatable, Codable, Sendable {
    public enum Kind: Equatable, Codable, Sendable {
        case remote(url: String, requirement: Requirement)
        case local(path: AbsolutePath)
    }

    public let kind: Kind

    /// The explicitly enabled traits. `nil` keeps the package defaults, while an empty array disables them.
    public let traits: [String]?

    public init(kind: Kind, traits: [String]? = nil) {
        self.kind = kind
        self.traits = traits
    }

    public static func remote(
        url: String,
        requirement: Requirement,
        traits: [String]? = nil
    ) -> Self {
        .init(kind: .remote(url: url, requirement: requirement), traits: traits)
    }

    public static func local(path: AbsolutePath, traits: [String]? = nil) -> Self {
        .init(kind: .local(path: path), traits: traits)
    }

    public var identity: String {
        let value = switch kind {
        case let .remote(url, _):
            url.split(separator: "/").last.map(String.init) ?? url
        case let .local(path):
            path.basename
        }
        let normalizedValue = value.lowercased()
        return normalizedValue.hasSuffix(".git") ? String(normalizedValue.dropLast(4)) : normalizedValue
    }

    public var isRemote: Bool {
        switch kind {
        case .remote:
            return true
        case .local:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case remote
        case local
    }

    private enum RemoteCodingKeys: String, CodingKey {
        case url
        case requirement
        case traits
    }

    private enum LocalCodingKeys: String, CodingKey {
        case path
        case traits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.typeMismatch(
                Self.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected exactly one package kind")
            )
        }

        switch key {
        case .remote:
            let remote = try container.nestedContainer(keyedBy: RemoteCodingKeys.self, forKey: .remote)
            self.init(
                kind: .remote(
                    url: try remote.decode(String.self, forKey: .url),
                    requirement: try remote.decode(Requirement.self, forKey: .requirement)
                ),
                traits: try remote.decodeIfPresent([String].self, forKey: .traits)
            )
        case .local:
            let local = try container.nestedContainer(keyedBy: LocalCodingKeys.self, forKey: .local)
            self.init(
                kind: .local(path: try local.decode(AbsolutePath.self, forKey: .path)),
                traits: try local.decodeIfPresent([String].self, forKey: .traits)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case let .remote(url, requirement):
            var remote = container.nestedContainer(keyedBy: RemoteCodingKeys.self, forKey: .remote)
            try remote.encode(url, forKey: .url)
            try remote.encode(requirement, forKey: .requirement)
            try remote.encodeIfPresent(traits, forKey: .traits)
        case let .local(path):
            var local = container.nestedContainer(keyedBy: LocalCodingKeys.self, forKey: .local)
            try local.encode(path, forKey: .path)
            try local.encodeIfPresent(traits, forKey: .traits)
        }
    }
}
