import Foundation
import TSCBasic

public enum FileElement: Equatable, Hashable, Codable {
    case file(path: AbsolutePath)
    case folderReference(path: AbsolutePath)

    public var path: AbsolutePath {
        switch self {
        case let .file(path):
            return path
        case let .folderReference(path):
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .file:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .file(path: path)
        case .folderReference:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .folderReference(path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
        case let .folderReference(path):
            try container.encode(Kind.folderReference, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
