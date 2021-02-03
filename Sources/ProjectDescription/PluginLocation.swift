import Foundation

/// The location to a directory containing a `Plugin` manifest.
public struct PluginLocation: Codable, Equatable {
    /// The type of location `local` or `git`.
    public let type: LocationType

    /// A `Path` to a directory containing a `Plugin` manifest.
    ///
    /// Example:
    /// ```
    /// .local(path: "/User/local/bin")
    /// ```
    public static func local(path: Path) -> Self {
        PluginLocation(type: .local(path: path))
    }

    /// A `URL` to a `git` repository pointing at a `tag`.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", tag: "1.0.0")
    /// ```
    public static func git(url: String, tag: String) -> Self {
        PluginLocation(type: .gitWithTag(url: url, tag: tag))
    }

    /// A `URL` to a `git` repository pointing at a commit `sha`.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", sha: "d06b4b3d")
    /// ```
    public static func git(url: String, sha: String) -> Self {
        PluginLocation(type: .gitWithSha(url: url, sha: sha))
    }
}

// MARK: - Codable

extension PluginLocation {
    public enum LocationType: Codable, Equatable {
        case local(path: Path)
        case gitWithTag(url: String, tag: String)
        case gitWithSha(url: String, sha: String)

        enum CodingKeys: CodingKey {
            case local
            case gitWithTag
            case gitWithSha
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .local(path):
                try container.encode(path, forKey: .local)
            case let .gitWithTag(url, tag):
                var nestedContainer = container.nestedUnkeyedContainer(forKey: .gitWithTag)
                try nestedContainer.encode(url)
                try nestedContainer.encode(tag)
            case let .gitWithSha(url, sha):
                var nestedContainer = container.nestedUnkeyedContainer(forKey: .gitWithSha)
                try nestedContainer.encode(url)
                try nestedContainer.encode(sha)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let key = container.allKeys.first

            switch key {
            case .local:
                let path = try container.decode(Path.self, forKey: .local)
                self = .local(path: path)
            case .gitWithTag:
                var nestedContainer = try container.nestedUnkeyedContainer(forKey: .gitWithTag)
                let url = try nestedContainer.decode(String.self)
                let tag = try nestedContainer.decode(String.self)
                self = .gitWithTag(url: url, tag: tag)
            case .gitWithSha:
                var nestedContainer = try container.nestedUnkeyedContainer(forKey: .gitWithSha)
                let url = try nestedContainer.decode(String.self)
                let sha = try nestedContainer.decode(String.self)
                self = .gitWithSha(url: url, sha: sha)
            case .none:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Unable to decode `LocationType`. \(String(describing: key)) is an unexpected key."
                    )
                )
            }
        }
    }
}
