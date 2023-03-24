import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class SchemeManifestMapperTests: TuistUnitTestCase {
    func test_from_when_the_scheme_has_no_actions() throws {
        // Given
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false
        )
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let generatorPaths = GeneratorPaths(manifestDirectory: projectPath)

        // When
        let model = try TuistGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        try assert(scheme: model, matches: manifest, path: projectPath, generatorPaths: generatorPaths)
    }

    func test_from_when_the_scheme_has_actions() throws {
        // Given
        let arguments = ProjectDescription.Arguments.test(
            environment: ["FOO": "BAR", "FIZ": "BUZZ"],
            launchArguments: [
                LaunchArgument(name: "--help", isEnabled: true),
                LaunchArgument(name: "subcommand", isEnabled: false),
            ]
        )

        let projectPath = try AbsolutePath(validating: "/somepath")
        let generatorPaths = GeneratorPaths(manifestDirectory: projectPath)

        let buildAction = ProjectDescription.BuildAction.test(targets: ["A", "B"])
        let runActions = ProjectDescription.RunAction.test(
            configuration: .release,
            executable: "A",
            arguments: arguments
        )
        let testAction = ProjectDescription.TestAction.test(
            targets: ["B"],
            arguments: arguments,
            configuration: .debug,
            coverage: true
        )
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: true,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runActions
        )

        // When
        let model = try TuistGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        try assert(scheme: model, matches: manifest, path: projectPath, generatorPaths: generatorPaths)
    }
}
