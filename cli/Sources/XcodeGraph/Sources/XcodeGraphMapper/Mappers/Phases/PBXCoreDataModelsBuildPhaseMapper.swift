import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping a set of resource files into `CoreDataModel` objects.
protocol PBXCoreDataModelsBuildPhaseMapping {
    /// Maps the provided resource files into an array of `CoreDataModel`.
    /// - Parameters:
    ///   - resourceFiles: The build files that might contain Core Data models.
    ///   - xcodeProj: The `XcodeProj` for resolving file paths.
    /// - Returns: An array of `CoreDataModel` objects.
    /// - Throws: If any paths are invalid.
    func map(_ resourceFiles: [PBXBuildFile], xcodeProj: XcodeProj) throws -> [CoreDataModel]
}

/// Maps `PBXBuildFile` objects to `CoreDataModel` domain models if they represent `.xcdatamodeld` files.
struct PBXCoreDataModelsBuildPhaseMapper: PBXCoreDataModelsBuildPhaseMapping {
    func map(_ resourceFiles: [PBXBuildFile], xcodeProj: XcodeProj) throws -> [CoreDataModel] {
        try resourceFiles.compactMap { try mapCoreDataModel($0, xcodeProj: xcodeProj) }
    }

    // MARK: - Private Helpers

    /// Converts a single `PBXBuildFile` into a `CoreDataModel` if it references a `.xcdatamodeld` version group.
    private func mapCoreDataModel(_ buildFile: PBXBuildFile, xcodeProj: XcodeProj) throws -> CoreDataModel? {
        guard let versionGroup = buildFile.file as? XCVersionGroup,
              versionGroup.path?.hasSuffix(FileExtension.coreData.rawValue) == true,
              let modelPathString = try versionGroup.fullPath(sourceRoot: xcodeProj.srcPathString)
        else {
            return nil
        }

        let modelPath = try AbsolutePath(validating: modelPathString)

        // Gather all child .xcdatamodel versions
        let versionPaths = versionGroup.children.compactMap(\.path)
        let resolvedVersions = try versionPaths.map {
            try AbsolutePath(validating: $0, relativeTo: modelPath)
        }

        // Current version defaults to the first if not explicitly set
        let currentVersion = versionGroup.currentVersion?.path ?? resolvedVersions.first?.pathString ?? ""

        return CoreDataModel(
            path: modelPath,
            versions: resolvedVersions,
            currentVersion: currentVersion
        )
    }
}
