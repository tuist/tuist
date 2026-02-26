import Foundation
import Path
import XcodeProj

// swiftlint:disable force_try
extension XCWorkspace {
    /// A computed property that either returns the workspace’s `path`
    public var workspacePath: AbsolutePath {
        try! AbsolutePath(validating: path!.string)
    }
}

extension XcodeProj {
    /// A computed property that either returns the project’s `path`
    public var projectPath: AbsolutePath {
        try! AbsolutePath(validating: path!.string)
    }

    public var srcPath: AbsolutePath {
        projectPath.parentDirectory
    }

    public var srcPathString: String {
        srcPath.pathString
    }
}

// swiftlint:enable force_try
