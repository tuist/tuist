import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class SchemeManifestMapperTests: TuistUnitTestCase {
    func test_from_when_the_scheme_has_no_actions() throws {
        // Given
        let manifest = ProjectDescription.Scheme.test(name: "Scheme",
                                                      shared: false)
        let projectPath = AbsolutePath("/somepath/Project")
        let generatorPaths = GeneratorPaths(manifestDirectory: projectPath)

        // When
        let model = try TuistCore.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        try assert(scheme: model, matches: manifest, path: projectPath, generatorPaths: generatorPaths)
    }

    func test_from_when_the_scheme_has_actions() throws {
        // Given
        let arguments = ProjectDescription.Arguments.test(environment: ["FOO": "BAR", "FIZ": "BUZZ"],
                                                          launchArguments: ["--help": true,
                                                                            "subcommand": false])

        let projectPath = AbsolutePath("/somepath")
        let generatorPaths = GeneratorPaths(manifestDirectory: projectPath)

        let buildAction = ProjectDescription.BuildAction.test(targets: ["A", "B"])
        let runActions = ProjectDescription.RunAction.test(config: .release,
                                                           executable: "A",
                                                           arguments: arguments)
        let testAction = ProjectDescription.TestAction.test(targets: ["B"],
                                                            arguments: arguments,
                                                            config: .debug,
                                                            coverage: true)
        let manifest = ProjectDescription.Scheme.test(name: "Scheme",
                                                      shared: true,
                                                      buildAction: buildAction,
                                                      testAction: testAction,
                                                      runAction: runActions)

        // When
        let model = try TuistCore.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        try assert(scheme: model, matches: manifest, path: projectPath, generatorPaths: generatorPaths)
    }
}
