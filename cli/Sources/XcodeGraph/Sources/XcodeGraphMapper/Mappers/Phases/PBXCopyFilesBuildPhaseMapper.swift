import Foundation
import Path
import XcodeGraph
import XcodeProj

/// A protocol for mapping `PBXCopyFilesBuildPhase` objects to `CopyFilesAction` models.
protocol PBXCopyFilesBuildPhaseMapping {
    /// Maps the provided copy files phases to an array of `CopyFilesAction`.
    /// - Parameters:
    ///   - copyFilesPhases: The build phases to map.
    ///   - xcodeProj: The `XcodeProj` containing project configuration and file references.
    /// - Returns: An array of mapped `CopyFilesAction`s.
    /// - Throws: If any file paths are invalid or cannot be resolved.
    func map(
        _ copyFilesPhases: [PBXCopyFilesBuildPhase],
        fileSystemSynchronizedGroups: [PBXFileSystemSynchronizedRootGroup],
        xcodeProj: XcodeProj
    ) throws -> [CopyFilesAction]
}

/// A mapper that converts `PBXCopyFilesBuildPhase` objects into `CopyFilesAction` domain models.
struct PBXCopyFilesBuildPhaseMapper: PBXCopyFilesBuildPhaseMapping {
    /// Maps the provided copy files phases to sorted `CopyFilesAction` models.
    func map(
        _ copyFilesPhases: [PBXCopyFilesBuildPhase],
        fileSystemSynchronizedGroups: [PBXFileSystemSynchronizedRootGroup],
        xcodeProj: XcodeProj
    ) throws -> [CopyFilesAction] {
        try copyFilesPhases
            .compactMap {
                try mapCopyFilesPhase(
                    $0,
                    fileSystemSynchronizedGroups: fileSystemSynchronizedGroups,
                    xcodeProj: xcodeProj
                )
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Private Helpers

    /// Converts a single `PBXCopyFilesBuildPhase` to a `CopyFilesAction`.
    /// - Parameters:
    ///   - phase: The `PBXCopyFilesBuildPhase` to convert.
    ///   - xcodeProj: The `XcodeProj` for path resolution.
    /// - Returns: A `CopyFilesAction` if the phase could be mapped, otherwise `nil`.
    /// - Throws: If file paths are invalid or unresolved.
    private func mapCopyFilesPhase(
        _ phase: PBXCopyFilesBuildPhase,
        fileSystemSynchronizedGroups: [PBXFileSystemSynchronizedRootGroup],
        xcodeProj: XcodeProj
    ) throws -> CopyFilesAction? {
        let files = try (phase.files ?? [])
            .compactMap { buildFile -> CopyFileElement? in
                guard let fileRef = buildFile.file,
                      let pathString = try fileRef.fullPath(sourceRoot: xcodeProj.srcPathString)
                else {
                    return nil
                }

                let absolutePath = try AbsolutePath(validating: pathString)
                let attributes = buildFile.attributes
                let codeSignOnCopy = attributes?.contains(BuildFileAttribute.codeSignOnCopy.rawValue) ?? false

                return .file(path: absolutePath, condition: nil, codeSignOnCopy: codeSignOnCopy)
            }
            .sorted { $0.path < $1.path }
        let groupsFiles = try fileSystemSynchronizedGroupsFiles(
            phase,
            fileSystemSynchronizedGroups: fileSystemSynchronizedGroups,
            xcodeProj: xcodeProj
        )

        return CopyFilesAction(
            name: phase.name ?? BuildPhaseConstants.copyFilesDefault,
            destination: mapDstSubfolderSpec(phase.dstSubfolderSpec),
            subpath: (phase.dstPath?.isEmpty == true) ? nil : phase.dstPath,
            files: files + groupsFiles
        )
    }

    private func fileSystemSynchronizedGroupsFiles(
        _ phase: PBXCopyFilesBuildPhase,
        fileSystemSynchronizedGroups: [PBXFileSystemSynchronizedRootGroup],
        xcodeProj: XcodeProj
    ) throws -> [CopyFileElement] {
        var files: [CopyFileElement] = []
        for fileSystemSynchronizedGroup in fileSystemSynchronizedGroups {
            if let path = fileSystemSynchronizedGroup.path {
                let buildPhaseExceptions = fileSystemSynchronizedGroup.exceptions?
                    .compactMap { $0 as? PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet }
                    .filter { $0.buildPhase == phase } ?? []
                let groupFiles = try buildPhaseExceptions.compactMap {
                    try $0.membershipExceptions?.map {
                        return CopyFileElement.file(
                            path: xcodeProj.srcPath.appending(component: path).appending(try RelativePath(validating: $0)),
                            condition: nil,
                            codeSignOnCopy: true
                        )
                    }
                }
                .flatMap { $0 }
                files.append(contentsOf: groupFiles)
            }
        }
        return files
    }

    /// Maps a `PBXCopyFilesBuildPhase.SubFolder` to a `CopyFilesAction.Destination`.
    private func mapDstSubfolderSpec(
        _ subfolderSpec: PBXCopyFilesBuildPhase.SubFolder?
    ) -> CopyFilesAction.Destination {
        switch subfolderSpec {
        case .absolutePath: return .absolutePath
        case .productsDirectory: return .productsDirectory
        case .wrapper: return .wrapper
        case .executables: return .executables
        case .resources: return .resources
        case .javaResources: return .javaResources
        case .frameworks: return .frameworks
        case .sharedFrameworks: return .sharedFrameworks
        case .sharedSupport: return .sharedSupport
        case .plugins: return .plugins
        default: return .productsDirectory
        }
    }
}
