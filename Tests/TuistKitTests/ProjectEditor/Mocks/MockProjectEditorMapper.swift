import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader

@testable import TuistCoreTesting
@testable import TuistKit

final class MockProjectEditorMapper: ProjectEditorMapping {
    var mapStub: ValueGraph?
    var mapArgs: [(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        tasks: [AbsolutePath],
        projectDescriptionPath: AbsolutePath,
        projectAutomationPath: AbsolutePath
    )] = []

    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        tasks: [AbsolutePath],
        projectDescriptionPath: AbsolutePath,
        projectAutomationPath: AbsolutePath
    ) throws -> ValueGraph {
        mapArgs.append((
            name: name,
            tuistPath: tuistPath,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifests,
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: pluginProjectDescriptionHelpersModule,
            helpers: helpers,
            templates: templates,
            tasks: tasks,
            projectDescriptionPath: projectDescriptionPath,
            projectAutomationPath: projectAutomationPath
        ))

        if let mapStub = mapStub { return mapStub }
        return ValueGraph.test()
    }
}
