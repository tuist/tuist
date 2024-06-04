import Foundation
import ProjectDescription
import TSCBasic
import XcodeProjectGenerator

extension XcodeProjectGenerator.Project {
    /// Maps a `ProjectDescription.Project` instance into a `XcodeProjectGenerator.Project` instance.
    /// Glob patterns in file elements are unfolded as part of the mapping.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the file element.
    ///   - generatorPaths: Generator paths.
    ///   - plugins: Configured plugins.
    ///   - externalDependencies: External dependencies graph.
    ///   - resourceSynthesizerPathLocator: Resource synthesizer locator.
    ///   - isExternal: Indicates whether the project is imported through `Dependencies.swift`.
    static func from(
        manifest: ProjectDescription.Project,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        externalDependencies: [String: [XcodeProjectGenerator.TargetDependency]],
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating,
        isExternal: Bool
    ) throws -> XcodeProjectGenerator.Project {
        let name = manifest.name
        let xcodeProjectName = manifest.options.xcodeProjectName ?? name
        let organizationName = manifest.organizationName
        let defaultKnownRegions = manifest.options.defaultKnownRegions
        let developmentRegion = manifest.options.developmentRegion
        let options = XcodeProjectGenerator.Project.Options.from(manifest: manifest.options)
        let settings = try manifest.settings.map { try XcodeProjectGenerator.Settings.from(manifest: $0, generatorPaths: generatorPaths) }

        let targets = try manifest.targets.map {
            try XcodeProjectGenerator.Target.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                externalDependencies: externalDependencies
            )
        }

        let schemes = try manifest.schemes.map { try XcodeProjectGenerator.Scheme.from(manifest: $0, generatorPaths: generatorPaths) }
        let additionalFiles = try manifest.additionalFiles
            .flatMap { try XcodeProjectGenerator.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }
        let packages = try manifest.packages.map { try XcodeProjectGenerator.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        let ideTemplateMacros = try manifest.fileHeaderTemplate
            .map { try IDETemplateMacros.from(manifest: $0, generatorPaths: generatorPaths) }
        let resourceSynthesizers = try manifest.resourceSynthesizers.map {
            try XcodeProjectGenerator.ResourceSynthesizer.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                plugins: plugins,
                resourceSynthesizerPathLocator: resourceSynthesizerPathLocator
            )
        }
        return Project(
            path: generatorPaths.manifestDirectory,
            sourceRootPath: generatorPaths.manifestDirectory,
            xcodeProjPath: generatorPaths.manifestDirectory.appending(component: "\(xcodeProjectName).xcodeproj"),
            name: name,
            organizationName: organizationName,
            defaultKnownRegions: defaultKnownRegions,
            developmentRegion: developmentRegion,
            options: options,
            settings: settings ?? .default,
            filesGroup: .group(name: "Project"),
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers,
            lastUpgradeCheck: nil,
            isExternal: isExternal
        )
    }
}
