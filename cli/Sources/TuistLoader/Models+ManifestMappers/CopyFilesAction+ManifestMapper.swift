import FileSystem
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.CopyFilesAction {
    /// Maps a ProjectDescription.CopyFilesAction instance into a XcodeGraph.CopyFilesAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.CopyFilesAction,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> XcodeGraph
        .CopyFilesAction
    {
        let result = try await manifest.files.concurrentMap { manifest -> [XcodeGraph.CopyFileElement] in
            do {
                let files = try await XcodeGraph.CopyFileElement.from(
                    manifest: manifest,
                    generatorPaths: generatorPaths,
                    fileSystem: fileSystem,
                    includeFiles: { XcodeGraph.Target.isResource(path: $0) }
                )
                return files.cleanPackages()
            } catch GlobError.nonExistentDirectory {
                return []
            }
        }

        let files = result.flatMap { $0 }

        return XcodeGraph.CopyFilesAction(
            name: manifest.name,
            destination: XcodeGraph.CopyFilesAction.Destination.from(manifest: manifest.destination),
            subpath: manifest.subpath,
            files: files
        )
    }
}

extension XcodeGraph.CopyFilesAction.Destination {
    /// Maps a ProjectDescription.TargetAction.Destination instance into a XcodeGraph.TargetAction.Destination model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action destination.
    static func from(manifest: ProjectDescription.CopyFilesAction.Destination) -> XcodeGraph.CopyFilesAction.Destination {
        switch manifest {
        case .absolutePath:
            return .absolutePath
        case .productsDirectory:
            return .productsDirectory
        case .wrapper:
            return .wrapper
        case .executables:
            return .executables
        case .resources:
            return .resources
        case .javaResources:
            return .javaResources
        case .frameworks:
            return .frameworks
        case .sharedFrameworks:
            return .sharedFrameworks
        case .sharedSupport:
            return .sharedSupport
        case .plugins:
            return .plugins
        case .other:
            return .other
        }
    }
}

// MARK: - Array Extension FileElement

extension [XcodeGraph.CopyFileElement] {
    /// Packages should be added as a whole folder not individually.
    /// (e.g. bundled file formats recognized by the OS like .pages, .numbers, .rtfd...)
    ///
    /// Given the input:
    /// ```
    /// /project/Templates/yellow.template/meta.json
    /// /project/Templates/yellow.template/image.png
    /// /project/Templates/blue.template/meta.json
    /// /project/Templates/blue.template/image.png
    /// /project/Fonts/somefont.ttf
    /// ```
    /// This is the output:
    /// ```
    /// /project/Templates/yellow.template
    /// /project/Templates/blue.template
    /// /project/Fonts/somefont.ttf
    /// ```
    ///
    /// - Returns: List of clean `AbsolutePath`s
    public func cleanPackages() -> [Self.Element] {
        compactMap {
            var filePath = $0.path
            while !filePath.isRoot {
                if filePath.parentDirectory.isPackage {
                    return nil
                } else if filePath.isPackage {
                    return $0
                } else {
                    filePath = filePath.parentDirectory
                }
            }
            return $0
        }
    }
}
