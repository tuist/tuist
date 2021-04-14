import Foundation
import TSCBasic

public enum ResourceFileElement: Equatable, Hashable, Codable {
    case file(path: AbsolutePath, tags: [String] = [])
    case folderReference(path: AbsolutePath, tags: [String] = [])

    public var path: AbsolutePath {
        switch self {
        case let .file(path, _):
            return path
        case let .folderReference(path, _):
            return path
        }
    }

    public var isReference: Bool {
        switch self {
        case .file:
            return false
        case .folderReference:
            return true
        }
    }

    public var tags: [String] {
        switch self {
        case let .file(_, tags):
            return tags
        case let .folderReference(_, tags):
            return tags
        }
    }
}

// MARK: - Codable

extension ResourceFileElement {
    private enum Kind: String, Codable {
        case file
        case folderReference
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .file:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let tags = try container.decode([String].self, forKey: .tags)
            self = .file(path: path, tags: tags)
        case .folderReference:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let tags = try container.decode([String].self, forKey: .tags)
            self = .folderReference(path: path, tags: tags)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path, tags):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(tags, forKey: .tags)
        case let .folderReference(path, tags):
            try container.encode(Kind.folderReference, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(tags, forKey: .tags)
        }
    }
}
