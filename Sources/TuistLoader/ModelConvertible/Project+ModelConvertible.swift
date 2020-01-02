import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Project: ModelConvertible {
    init(manifest: ProjectDescription.Project, generatorPaths: GeneratorPaths) throws {
        let name = manifest.name

        let settings = try manifest.settings.map { try TuistCore.Settings(manifest: $0, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map {
            try TuistCore.Target(manifest: $0, generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme(manifest: $0, generatorPaths: generatorPaths) }

        let additionalFiles = try manifest.additionalFiles.compactMap {
            try TuistCore.FileElements(manifest: $0, generatorPaths: generatorPaths)
        }

        let packages = try manifest.packages.map { package in
            try TuistCore.Package(manifest: package, generatorPaths: generatorPaths)
        }

        self.init(path: generatorPaths.manifestDirectory,
                  name: name,
                  settings: settings ?? .default,
                  filesGroup: .group(name: "Project"),
                  targets: targets,
                  packages: packages,
                  schemes: schemes,
                  additionalFiles: additionalFiles)
    }
}
