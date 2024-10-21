import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Project {
    /// Maps a `ProjectDescription.Project` instance into a `XcodeGraph.Project` instance.
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
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating,
        isExternal: Bool
    ) async throws -> XcodeGraph.Project {
        let name = manifest.name
        let xcodeProjectName = manifest.options.xcodeProjectName ?? name
        let organizationName = manifest.organizationName
        let classPrefix = manifest.classPrefix
        let defaultKnownRegions = manifest.options.defaultKnownRegions
        let developmentRegion = manifest.options.developmentRegion
        let options = XcodeGraph.Project.Options.from(manifest: manifest.options)
        let settings = try manifest.settings.map { try XcodeGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }

        let targets = try await manifest.targets.concurrentMap {
            try await XcodeGraph.Target.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                externalDependencies: externalDependencies
            )
        }

        let schemes = try await manifest.schemes.concurrentMap { try await XcodeGraph.Scheme.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let additionalFiles = try await manifest.additionalFiles
            .concurrentMap { try await XcodeGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }
            .flatMap { $0 }
        let packages = try manifest.packages.map { try XcodeGraph.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        let ideTemplateMacros = try manifest.fileHeaderTemplate
            .map { try IDETemplateMacros.from(manifest: $0, generatorPaths: generatorPaths) }
        let resourceSynthesizers = try await manifest.resourceSynthesizers.concurrentMap {
            try await XcodeGraph.ResourceSynthesizer.from(
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
            classPrefix: classPrefix,
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
