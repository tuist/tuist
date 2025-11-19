import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

public enum XcodeProjectOrWorkspacePathLocatingError: Equatable, LocalizedError {
    case xcodeProjectOrWorkspaceNotFound(AbsolutePath)

    public var errorDescription: String? {
        switch self {
        case let .xcodeProjectOrWorkspaceNotFound(path):
            return "No Xcode project or workspace found at \(path.pathString). Make sure it exists."
        }
    }
}

@Mockable
public protocol XcodeProjectOrWorkspacePathLocating {
    func locate(from path: AbsolutePath) async throws -> AbsolutePath
}

public struct XcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func locate(from path: AbsolutePath) async throws -> AbsolutePath {
        if let workspacePath = Environment.current.workspacePath {
            if workspacePath.parentDirectory.extension == "xcodeproj" {
                return workspacePath.parentDirectory
            } else {
                return workspacePath
            }
        } else {
            if let workspacePath = try await fileSystem.glob(
                directory: path,
                include: ["*.xcworkspace"]
            )
            .collect()
            .first {
                return workspacePath
            } else if let xcodeProjPath = try await fileSystem.glob(
                directory: path,
                include: ["*.xcodeproj"]
            )
            .collect()
            .first {
                return xcodeProjPath
            } else {
                throw XcodeProjectOrWorkspacePathLocatingError.xcodeProjectOrWorkspaceNotFound(path)
            }
        }
    }
}
