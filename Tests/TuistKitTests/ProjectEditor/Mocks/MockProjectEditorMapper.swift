import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting

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
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
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
        pluginManifests: [AbsolutePath],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
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
            pluginManifests: pluginManifests,
            helpers: helpers,
            templates: templates,
            projectDescriptionPath: projectDescriptionPath
        ))

        if let mapStub = mapStub { return mapStub }
        return ValueGraph.test()
    }
}
