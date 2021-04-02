import Foundation
import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.Project {
    /// Maps a ProjectDescription.FileElement instance into a [TuistGraph.FileElement] instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the file element.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Project,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        pluginsHelper: PluginsHelping
    ) throws -> TuistGraph.Project {
        let name = manifest.name
        let organizationName = manifest.organizationName
        let settings = try manifest.settings.map { try TuistGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map { try TuistGraph.Target.from(manifest: $0, generatorPaths: generatorPaths) }
        let schemes = try manifest.schemes.map { try TuistGraph.Scheme.from(manifest: $0, generatorPaths: generatorPaths) }
        let additionalFiles = try manifest.additionalFiles.flatMap { try TuistGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }
        let packages = try manifest.packages.map { try TuistGraph.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        let ideTemplateMacros = try manifest.fileHeaderTemplate.map { try IDETemplateMacros.from(manifest: $0, generatorPaths: generatorPaths) }
        let resourceSynthesizers = try manifest.resourceSynthesizers.map {
            try TuistGraph.ResourceSynthesizer.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                plugins: plugins,
                pluginsHelper: pluginsHelper
            )            
        }
        return Project(
            path: generatorPaths.manifestDirectory,
            sourceRootPath: generatorPaths.manifestDirectory,
            xcodeProjPath: generatorPaths.manifestDirectory.appending(component: "\(name).xcodeproj"),
            name: name,
            organizationName: organizationName,
            developmentRegion: nil,
            settings: settings ?? .default,
            filesGroup: .group(name: "Project"),
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers
        )
    }
}
