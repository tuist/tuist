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
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    )] = []

    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionSearchPath: AbsolutePath
    ) throws -> Graph {
        mapArgs.append((
            name: name,
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifests,
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: pluginProjectDescriptionHelpersModule,
            helpers: helpers,
            templates: templates,
            projectDescriptionPath: projectDescriptionSearchPath
        ))

        if let mapStub = mapStub { return mapStub }
        return Graph.test()
    }
}
