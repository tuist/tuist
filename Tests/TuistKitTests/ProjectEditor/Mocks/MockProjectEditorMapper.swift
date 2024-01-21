import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader

@testable import TuistCoreTesting
@testable import TuistKit

final class MockProjectEditorMapper: ProjectEditorMapping {
    var mapStub: Graph?
    var mapArgs: [(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        configPath: AbsolutePath?,
        packageManifestPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templateSources: [AbsolutePath],
        templateResources: [AbsolutePath],
        resourceSynthesizers: [AbsolutePath],
        stencils: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    )] = []

    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        configPath: AbsolutePath?,
        packageManifestPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templateSources: [AbsolutePath],
        templateResources: [AbsolutePath],
        resourceSynthesizers: [AbsolutePath],
        stencils: [AbsolutePath],
        projectDescriptionSearchPath: AbsolutePath
    ) throws -> Graph {
        mapArgs.append((
            name: name,
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
            configPath: configPath,
            packageManifestPath: packageManifestPath,
            projectManifests: projectManifests,
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: pluginProjectDescriptionHelpersModule,
            helpers: helpers,
            templateSources: templateSources,
            templateResources: templateResources,
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionPath: projectDescriptionSearchPath
        ))

        if let mapStub { return mapStub }
        return Graph.test()
    }
}
