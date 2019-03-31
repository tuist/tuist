import Basic
import Foundation

public enum WorkspaceElement: Equatable {
    case file(path: AbsolutePath)
    case folderReference(path: AbsolutePath)

    var path: AbsolutePath {
        switch self {
        case let .file(path):
            return path
        case let .folderReference(path):
            return path
        }
    }

    var isReference: Bool {
        switch self {
        case .file:
            return false
        case .folderReference:
            return true
        }
    }
}
