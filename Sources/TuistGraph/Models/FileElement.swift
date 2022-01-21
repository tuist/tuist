import Foundation
import TSCBasic

public enum FileElement: Equatable, Hashable, Codable {
    case file(path: AbsolutePath, group: String?)
    case folderReference(path: AbsolutePath, group: String?)

    public var path: AbsolutePath {
        switch self {
        case let .file(path, _):
            return path
        case let .folderReference(path, _):
            return path
        }
    }

    public var group: String? {
        switch self {
        case let .file(_, group):
            return group
        case let .folderReference(_, group):
            return group
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
}

// MARK: - Codable

extension FileElement {
    private enum Kind: String, Codable {
        case file
        case folderReference
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let group = try container.decodeIfPresent(String.self, forKey: .group)
        switch kind {
        case .file:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .file(path: path, group: group)
        case .folderReference:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .folderReference(path: path, group: group)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path, group):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(group, forKey: .group)
        case let .folderReference(path, group):
            try container.encode(Kind.folderReference, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(group, forKey: .group)
        }
    }
}
