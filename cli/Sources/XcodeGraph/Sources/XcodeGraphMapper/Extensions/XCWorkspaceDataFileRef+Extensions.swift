import Path
import XcodeProj

extension XCWorkspaceDataFileRef {
    /// Resolves the absolute path referenced by this `XCWorkspaceDataFileRef`.
    ///
    /// - Parameter srcPath: The workspace source root path.
    /// - Returns: The resolved `AbsolutePath` of this file reference.
    func path(
        srcPath: AbsolutePath,
        developerDirectoryProvider: DeveloperDirectoryProviding = DeveloperDirectoryProvider()
    ) async throws -> AbsolutePath {
        switch location {
        case let .absolute(path):
            return try AbsolutePath(validating: path)
        case let .container(subPath):
            let relativePath = try RelativePath(validating: subPath)
            return srcPath.appending(relativePath)
        case let .developer(subPath):
            return try AbsolutePath(
                validating: subPath,
                relativeTo: try await developerDirectoryProvider.developerDirectory()
            )
        case let .group(subPath):
            // Group paths are relative to the workspace file itself
            let relativePath = try RelativePath(validating: subPath)
            return srcPath.appending(relativePath)
        case let .current(subPath):
            // Current paths are relative to the current directory
            let relativePath = try RelativePath(validating: subPath)
            return srcPath.appending(relativePath)
        case let .other(type, subPath):
            // Other path types: prefix with the type and append subpath
            let relativePath = try RelativePath(validating: "\(type)/\(subPath)")
            return srcPath.appending(relativePath)
        }
    }
}
