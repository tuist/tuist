import Foundation
import TSCBasic

public enum ResourceFileElement: Equatable, Hashable, Codable {
    /// A file path (or glob pattern) to include, a list of file paths (or glob patterns) to exclude, and ODR tags list. For convenience, a string literal can be used as an alternate way to specify this option.
    case file(path: AbsolutePath, tags: [String] = [])
    /// A directory path to include as a folder reference and ODR tags list.
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

    public init(path: AbsolutePath) {
        self = .file(path: path)
    }
}

extension Array where Element == TuistGraph.ResourceFileElement {
    public mutating func remove(path: AbsolutePath) {
        guard let index = firstIndex(of: TuistGraph.ResourceFileElement(path: path)) else { return }
        remove(at: index)
    }
}
