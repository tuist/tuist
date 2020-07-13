import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.Project {
    /// Maps a ProjectDescription.FileElement instance into a [TuistCore.FileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the file element.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Project,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Project {
        let name = manifest.name
        let organizationName = manifest.organizationName
        let settings = try manifest.settings.map { try TuistCore.Settings.from(manifest: $0, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map { try TuistCore.Target.from(manifest: $0, generatorPaths: generatorPaths) }
        let schemes = try manifest.schemes.map { try TuistCore.Scheme.from(manifest: $0, generatorPaths: generatorPaths) }
        let additionalFiles = try manifest.additionalFiles.flatMap { try TuistCore.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }
        let packages = try manifest.packages.map { try TuistCore.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        return Project(path: generatorPaths.manifestDirectory,
                       sourceRootPath: generatorPaths.manifestDirectory,
                       name: name,
                       organizationName: organizationName,
                       fileName: nil,
                       settings: settings ?? .default,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
                       packages: packages,
                       schemes: schemes,
                       additionalFiles: additionalFiles)
    }

    func adding(target: TuistCore.Target) -> TuistCore.Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets + [target],
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    func replacing(fileName: String?) -> TuistCore.Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    func replacing(organizationName: String?) -> TuistCore.Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}
