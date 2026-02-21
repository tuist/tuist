import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderExceptions {
    static func from(
        manifest: ProjectDescription.BuildableFolderExceptions,
        buildableFolder: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> Self {
        var exceptions: [XcodeGraph.BuildableFolderException] = []
        for exception in manifest.exceptions {
            let mapped = try await XcodeGraph.BuildableFolderException.from(
                manifest: exception,
                buildableFolder: buildableFolder,
                fileSystem: fileSystem
            )
            exceptions.append(mapped)
        }
        return Self(exceptions: exceptions)
    }
}
