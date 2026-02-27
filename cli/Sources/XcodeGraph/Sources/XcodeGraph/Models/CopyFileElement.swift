import Foundation
import Path

public enum CopyFileElement: Equatable, Hashable, Codable, Sendable {
    case file(path: AbsolutePath, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)
    case folderReference(path: AbsolutePath, condition: PlatformCondition? = nil, codeSignOnCopy: Bool = false)

    public var path: AbsolutePath {
        switch self {
        case let .file(path, _, _):
            return path
        case let .folderReference(path, _, _):
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
        case let .file(_, condition, _), let .folderReference(_, condition, _):
            return condition
        }
    }

    public var codeSignOnCopy: Bool {
        switch self {
        case let .file(_, _, codeSignOnCopy), let .folderReference(_, _, codeSignOnCopy):
            return codeSignOnCopy
        }
    }
}
