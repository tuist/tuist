import Foundation
import TSCBasic

public enum CopyFileElement: Equatable, Hashable, Codable {
    case file(path: AbsolutePath, condition: PlatformCondition? = nil)
    case folderReference(path: AbsolutePath, condition: PlatformCondition? = nil)

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

    public var condition: PlatformCondition? {
        switch self {
        case let .file(_, condition), let .folderReference(_, condition):
            return condition
        }
    }
}
