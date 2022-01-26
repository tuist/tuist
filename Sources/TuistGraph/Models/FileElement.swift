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
