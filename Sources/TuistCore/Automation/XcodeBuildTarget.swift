import Foundation
import TSCBasic

public enum XcodeBuildTarget: Equatable {
    /// The target is an Xcode project.
    case project(AbsolutePath)

    /// The target is an Xcode workspace.
    case workspace(AbsolutePath)

    public init(with path: AbsolutePath) {
        switch path.extension {
        case "xcworkspace":
            self = .workspace(path)
        default:
            self = .project(path)
        }
    }

    /// Returns the arguments that need to be passed to xcodebuild to build this target.
    public var xcodebuildArguments: [String] {
        switch self {
        case let .project(path):
            return ["-project", path.pathString]
        case let .workspace(path):
            return ["-workspace", path.pathString]
        }
    }

    public var path: AbsolutePath {
        switch self {
        case let .project(path), let .workspace(path):
            return path
        }
    }
}
