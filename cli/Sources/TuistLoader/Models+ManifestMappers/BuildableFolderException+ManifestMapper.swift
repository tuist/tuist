import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderException {
    static func from(
        manifest: ProjectDescription.BuildableFolderException,
        buildableFolder: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> Self {
        var excluded: [AbsolutePath] = []
        for pattern in manifest.excluded {
            let expandedPaths = try await fileSystem.glob(directory: buildableFolder, include: [pattern]).collect()
            excluded.append(contentsOf: expandedPaths)
        }

        let compilerFlags = Dictionary(uniqueKeysWithValues: try manifest.compilerFlags.map {
            (buildableFolder.appending(try RelativePath(validating: $0.0)), $0.1)
        })
        let publicHeaders = try manifest.publicHeaders.map { buildableFolder.appending(try RelativePath(validating: $0)) }
        let privateHeaders = try manifest.privateHeaders.map { buildableFolder.appending(try RelativePath(validating: $0)) }
        let platformFilters = Dictionary(uniqueKeysWithValues: try manifest.platformFilters.compactMap {
            key, filters -> (AbsolutePath, XcodeGraph.PlatformCondition)? in
            guard let condition = XcodeGraph.PlatformCondition.when(filters.asGraphFilters) else { return nil }
            return (buildableFolder.appending(try RelativePath(validating: key)), condition)
        })
        return Self(
            excluded: excluded,
            compilerFlags: compilerFlags,
            publicHeaders: publicHeaders,
            privateHeaders: privateHeaders,
            platformFilters: platformFilters
        )
    }
}
