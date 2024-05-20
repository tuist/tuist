import Foundation
import TSCBasic

public enum CopyFileElement: Equatable, Hashable, Codable {
    case file(path: AbsolutePath, condition: PlatformCondition? = nil, codeSign: Bool = false)
    case folderReference(path: AbsolutePath, condition: PlatformCondition? = nil, codeSign: Bool = false)

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
    
    public var codeSign: Bool {
        switch self {
        case let .file(_, _, codesign), let .folderReference(_, _, codesign):
            return codesign
        }
    }
}
