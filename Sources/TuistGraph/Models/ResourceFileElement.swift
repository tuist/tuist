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
