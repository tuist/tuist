import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Project {
        let name = manifest.name

        let settings = try manifest.settings.map { try TuistCore.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map {
            try TuistCore.Target.from(manifest: $0,
                                      path: path,
                                      generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme.from(manifest: $0, projectPath: path, generatorPaths: generatorPaths) }

        let additionalFiles = try manifest.additionalFiles.flatMap {
            try TuistCore.FileElement.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths)
        }

        let packages = try manifest.packages.map { package in
            try TuistCore.Package.from(manifest: package, path: path, generatorPaths: generatorPaths)
        }

        return Project(path: path,
                       name: name,
                       settings: settings ?? .default,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
                       packages: packages,
                       schemes: schemes,
                       additionalFiles: additionalFiles)
    }

    func adding(target: TuistCore.Target) -> TuistCore.Project {
        Project(path: path,
                name: name,
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
                name: name,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}
