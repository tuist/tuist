import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct SchemeManifestMapperTests {
    @Test(.inTemporaryDirectory) func from_when_the_scheme_has_no_actions() async throws {
        // Given
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false
        )
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )

        // When
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.name == manifest.name)
        #expect(model.shared == manifest.shared)
    }

    @Test(.inTemporaryDirectory) func from_when_the_scheme_has_actions() async throws {
        // Given
        let arguments = ProjectDescription.Arguments.test(
            environment: ["FOO": "BAR", "FIZ": "BUZZ"],
            launchArguments: [
                .launchArgument(name: "--help", isEnabled: true),
                .launchArgument(name: "subcommand", isEnabled: false),
            ]
        )

        let projectPath = try AbsolutePath(validating: "/somepath")
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )

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
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.name == manifest.name)
        #expect(model.shared == manifest.shared)
        #expect(model.buildAction != nil)
        #expect(model.testAction != nil)
        #expect(model.runAction != nil)
    }

    @Test(.inTemporaryDirectory) func from_when_the_scheme_uses_manual_build_order() async throws {
        // Given
        let buildAction = ProjectDescription.BuildAction.test(
            targets: ["A", "B"],
            buildOrder: .manual
        )
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false,
            buildAction: buildAction
        )
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )

        // When
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.buildAction?.parallelizeBuild == false)
    }

    @Test(.inTemporaryDirectory) func from_when_the_run_action_has_askForAppToLaunch() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )
        let runAction = ProjectDescription.RunAction.test(askForAppToLaunch: true)
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false,
            runAction: runAction
        )

        // When
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.runAction?.askForAppToLaunch == true)
    }

    @Test(.inTemporaryDirectory) func from_when_the_profile_action_has_askForAppToLaunch() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )
        let profileAction = ProjectDescription.ProfileAction.profileAction(
            executable: .askOnLaunch
        )
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false,
            profileAction: profileAction
        )

        // When
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.profileAction?.askForAppToLaunch == true)
    }

    @Test(.inTemporaryDirectory) func from_when_the_scheme_uses_custom_executable_and_working_directory() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let runAction = ProjectDescription.RunAction.test(
            customWorkingDirectory: "/home/user/dev/project",
            filePath: "/usr/bin/my-script"
        )
        let manifest = ProjectDescription.Scheme.test(
            name: "Scheme",
            shared: false,
            runAction: runAction
        )
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: projectPath,
            rootDirectory: rootDirectory
        )

        // When
        let model = try await XcodeGraph.Scheme.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        #expect(model.runAction?.executable == nil)
        #expect(model.runAction?.customWorkingDirectory == "/home/user/dev/project")
        #expect(model.runAction?.filePath == "/usr/bin/my-script")
    }
}
