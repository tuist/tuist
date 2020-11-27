import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

public enum CopyFilesManifestMapperError: FatalError {
    case invalidResourcesGlob(actionName: String, invalidGlobs: [InvalidGlob])

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidResourcesGlob(actionName: actionName, invalidGlobs: invalidGlobs):
            return "The copy files action \(actionName) has the following invalid resource globs:\n" + invalidGlobs.invalidGlobsDescription
        }
    }
}

extension TuistCore.CopyFilesAction {
    /// Maps a ProjectDescription.CopyFilesAction instance into a TuistCore.CopyFilesAction instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CopyFilesAction, generatorPaths: GeneratorPaths) throws -> TuistCore.CopyFilesAction {
        var invalidResourceGlobs: [InvalidGlob] = []
        let files: [TuistCore.FileElement] = try manifest.files.flatMap { manifest -> [TuistCore.FileElement] in
            do {
                return try TuistCore.FileElement.from(manifest: manifest,
                                                      generatorPaths: generatorPaths,
                                                      includeFiles: { TuistCore.Target.isResource(path: $0) })
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                invalidResourceGlobs.append(invalidGlob)
                return []
            }
        }

        if !invalidResourceGlobs.isEmpty {
            throw CopyFilesManifestMapperError.invalidResourcesGlob(actionName: manifest.name, invalidGlobs: invalidResourceGlobs)
        }

        return TuistCore.CopyFilesAction(
            name: manifest.name,
            destination: TuistCore.CopyFilesAction.Destination.from(manifest: manifest.destination),
            subpath: manifest.subpath,
            files: files
        )
    }
}

extension TuistCore.CopyFilesAction.Destination {
    /// Maps a ProjectDescription.TargetAction.Destination instance into a TuistCore.TargetAction.Destination model.
    /// - Parameters:
    ///   - manifest: Manifest representation of target action destination.
    static func from(manifest: ProjectDescription.CopyFilesAction.Destination) -> TuistCore.CopyFilesAction.Destination {
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
