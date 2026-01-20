/// Queries for matching against a target in manifests.
public enum TargetQuery: Codable, Equatable, Sendable {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)

    private enum CodingKeys: String, CodingKey {
        case named
        case tagged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .named) {
            self = .named(name)
        } else if let tag = try container.decodeIfPresent(String.self, forKey: .tagged) {
            self = .tagged(tag)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid TargetQuery encoding")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .named(name):
            try container.encode(name, forKey: .named)
        case let .tagged(tag):
            try container.encode(tag, forKey: .tagged)
        }
    }
}

extension TargetQuery: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let tagPrefix = "tag:"
        if value.hasPrefix(tagPrefix) {
            self = .tagged(String(value.dropFirst(tagPrefix.count)))
        } else {
            self = .named(value)
        }
    }
}
