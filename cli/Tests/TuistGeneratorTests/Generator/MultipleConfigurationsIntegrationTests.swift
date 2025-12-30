import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistTesting

final class MultipleConfigurationsIntegrationTests {
    init() async throws {
        let mockSwiftVersionProvider = try #require(SwiftVersionProvider.mocked)
        given(mockSwiftVersionProvider)
            .swiftVersion()
            .willReturn("5.2")

        let mockXcodeController = try #require(XcodeController.mocked)
        given(mockXcodeController)
            .selectedVersion()
            .willReturn(TSCUtility.Version(11, 0, 0))
        try await setupTestProject()
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateThrowsLintingErrorWhenConfigurationsAreEmpty() async throws {
        // Given
        let projectSettings = Settings(configurations: [:])
        let targetSettings: Settings? = nil

        // When / Then
        await #expect(throws: Error.self, performing: {
            try await self.generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)
        })
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenSingleDebugConfigurationInProject() async throws {
        // Given
        let projectSettings = Settings(
            base: ["A": "A"],
            configurations: [.debug: nil]
        )

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        try assertProject(expectedConfigurations: ["Debug"])
        try assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        #expect(debug.contains("A", "A") == true) // from base
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenConfigurationSettingsOverrideXCConfig() async throws {
        // Given
        let debugFilePath = try createFile(path: "Configs/debug.xcconfig", content: """
        A=A_XCCONFIG
        B=B_XCCONFIG
        """)
        let debugConfiguration = Configuration(
            settings: ["A": "A", "C": "C"],
            xcconfig: debugFilePath
        )
        let projectSettings = Settings(configurations: [.debug: debugConfiguration])

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        try assertProject(expectedConfigurations: ["Debug"])
        try assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        #expect(debug.contains("A", "A") == true) // from settings overriding .xcconfig
        #expect(debug.contains("B", "B_XCCONFIG") == true) // from .xcconfig
        #expect(debug.contains("C", "C") == true) // from settings
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenConfigurationSettingsOverrideBase() async throws {
        // Given
        let debugConfiguration = Configuration(settings: ["A": "A", "C": "C"])
        let projectSettings = Settings(
            base: ["A": "A_BASE", "B": "B_BASE"],
            configurations: [.debug: debugConfiguration]
        )

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        try assertProject(expectedConfigurations: ["Debug"])
        try assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        #expect(debug.contains("A", "A") == true) // from configuration settings overriding base
        #expect(debug.contains("B", "B_BASE") == true) // from base
        #expect(debug.contains("C", "C") == true) // from settings
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenBuildConfigurationWithCustomName() async throws {
        // Given
        let customConfiguration = Configuration(settings: ["A": "A", "C": "C"])
        let projectSettings = Settings(
            base: ["A": "A_BASE", "B": "B_BASE"],
            configurations: [
                .debug("Custom"): customConfiguration,
                .release: nil,
            ]
        )

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        try assertProject(expectedConfigurations: ["Custom", "Release"])
        try assertTarget(expectedConfigurations: ["Custom", "Release"])

        let custom = try extractWorkspaceSettings(configuration: "Custom")
        #expect(custom.contains("A", "A") == true) // from custom settings overriding base
        #expect(custom.contains("B", "B_BASE") == true) // from base
        #expect(custom.contains("C", "C") == true) // from custom settings

        let release = try extractWorkspaceSettings(configuration: "Release")
        #expect(release.contains("A", "A_BASE") == true) // from base
        #expect(release.contains("B", "B_BASE") == true) // from base
        #expect(release.contains("C", "C") == false) // non-existing, only defined in Custom
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenTargetSettingsOverrideTargetXCConfig() async throws {
        // Given
        let debugFilePath = try createFile(path: "Configs/debug.xcconfig", content: """
        A=A_XCCONFIG
        B=B_XCCONFIG
        """)
        let debugConfiguration = Configuration(
            settings: ["A": "A", "C": "C"],
            xcconfig: debugFilePath
        )
        let projectSettings = Settings(configurations: [.debug: nil])
        let targetSettings = Settings(configurations: [.debug: debugConfiguration])

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        try assertProject(expectedConfigurations: ["Debug"])
        try assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Custom")
        #expect(debug.contains("A", "A") == true) // from target settings overriding target .xcconfig
        #expect(debug.contains("B", "B_XCCONFIG") == true) // from target .xcconfig
        #expect(debug.contains("C", "C") == true) // from target settings
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenMultipleConfigurations() async throws {
        // Given
        let projectDebugConfiguration = Configuration(settings: [
            "A": "A_PROJECT_DEBUG",
            "B": "B_PROJECT_DEBUG",
        ])
        let projectReleaseConfiguration = Configuration(settings: [
            "A": "A_PROJECT_RELEASE",
            "C": "C_PROJECT_RELEASE",
        ])
        let projectSettings = Settings(configurations: [
            .debug: projectDebugConfiguration,
            .release("ProjectRelease"): projectReleaseConfiguration,
        ])

        let targetDebugConfiguration = Configuration(settings: ["B": "B_TARGET_DEBUG"])
        let targetStagingConfiguration = Configuration(settings: ["B": "B_TARGET_STAGING"])

        let targetSettings = Settings(configurations: [
            .debug: targetDebugConfiguration,
            .release("Staging"): targetStagingConfiguration,
        ])

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        try assertProject(expectedConfigurations: ["Debug", "ProjectRelease"])
        try assertTarget(expectedConfigurations: ["Debug", "ProjectRelease", "Staging"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        #expect(debug.contains("A", "A_PROJECT_DEBUG") == true) // from project debug settings
        #expect(debug.contains("B", "B_TARGET_DEBUG") == true) // from target debug settings

        let release = try extractWorkspaceSettings(configuration: "ProjectRelease")
        #expect(release.contains("A", "A_PROJECT_RELEASE") == true) // from project debug settings
        #expect(release.contains("C", "C_PROJECT_RELEASE") == true) // from project debug settings
        #expect(release.containsKey("B") == false) // non-existing

        let staging = try extractWorkspaceSettings(configuration: "Staging")
        #expect(staging.contains("B", "B_TARGET_STAGING") == true) // from target staging settings
        #expect(staging.containsKey("A") == false) // non-existing
        #expect(staging.containsKey("C") == false) // non-existing
    }

    /// Exhaustive test to validate the priority of the particular settings:
    /// - project .xcconfig
    /// - project base
    /// - project configuration settings
    /// - target .xcconfig
    /// - target base
    /// - target configuraiton settings
    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenTargetSettingsOverrideProjectBaseSettingsAndXCConfig() async throws {
        // Given
        let projectDebugFilePath = try createFile(path: "Configs/project_debug.xcconfig", content: """
        A=A_PROJECT_XCCONFIG
        B=B_PROJECT_XCCONFIG
        C=C_PROJECT_XCCONFIG
        D=D_PROJECT_XCCONFIG
        E=E_PROJECT_XCCONFIG
        F=F_PROJECT_XCCONFIG
        PROJECT_XCCONFIG=YES
        """)
        let projectDebugConfiguration = Configuration(
            settings: [
                "C": "C_PROJECT",
                "D": "D_PROJECT",
                "E": "E_PROJECT",
                "F": "F_PROJECT",
                "PROJECT": "YES",
            ],
            xcconfig: projectDebugFilePath
        )

        let projectSettings = Settings(
            base: [
                "B": "B_PROJECT_BASE",
                "C": "C_PROJECT_BASE",
                "D": "D_PROJECT_BASE",
                "E": "E_PROJECT_BASE",
                "F": "F_PROJECT_BASE",
                "PROJECT_BASE": "YES",
            ],
            configurations: [.debug: projectDebugConfiguration]
        )

        let targetDebugFilePath = try createFile(path: "Configs/target_debug.xcconfig", content: """
        D=D_TARGET_XCCONFIG
        E=E_TARGET_XCCONFIG
        F=F_TARGET_XCCONFIG
        TARGET_XCCONFIG=YES
        """)

        let targetDebugConfiguration = Configuration(
            settings: [
                "F": "F_TARGET",
                "TARGET": "YES",
            ],
            xcconfig: targetDebugFilePath
        )
        let targetSettings = Settings(
            base: [
                "E": "E_TARGET_BASE",
                "F": "E_TARGET_BASE",
                "TARGET_BASE": "YES",
            ],
            configurations: [.debug: targetDebugConfiguration]
        )

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        try assertProject(expectedConfigurations: ["Debug"])
        try assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        #expect(debug.contains("A", "A_PROJECT_XCCONFIG") == true) // from project .xcconfig
        #expect(debug.contains("B", "B_PROJECT_BASE") == true) // from project base
        #expect(debug.contains("C", "C_PROJECT") == true) // from project settings
        #expect(debug.contains("D", "D_TARGET_XCCONFIG") == true) // from target .xcconfig
        #expect(debug.contains("E", "E_TARGET_BASE") == true) // from target base
        #expect(debug.contains("F", "F_TARGET") == true) // from target settings
        #expect(debug.contains("PROJECT_XCCONFIG", "YES") == true) // from project .xcconfig
        #expect(debug.contains("PROJECT_BASE", "YES") == true) // from project base
        #expect(debug.contains("PROJECT", "YES") == true) // from project settings
        #expect(debug.contains("TARGET_XCCONFIG", "YES") == true) // from target .xcconfig
        #expect(debug.contains("TARGET_BASE", "YES") == true) // from target base
        #expect(debug.contains("TARGET", "YES") == true) // from target settings
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWhenCustomConfigurations() async throws {
        // Given
        let projectDebugConfiguration = Configuration(settings: [
            "A": "A_PROJECT_DEBUG",
            "B": "B_PROJECT_DEBUG",
        ])
        let projectCustomDebugConfiguration = Configuration(settings: [
            "A": "A_PROJECT_RELEASE",
            "C": "C_PROJECT_RELEASE",
        ])
        let projectReleaseConfiguration = Configuration(settings: [:])
        let projectCustomReleaseConfiguration = Configuration(settings: ["E": "E_PROJECT_RELEASE"])
        let projectSettings = Settings(configurations: [
            .debug: projectDebugConfiguration,
            .debug("CustomDebug"): projectCustomDebugConfiguration,
            .release: projectReleaseConfiguration,
            .release("CustomRelease"): projectCustomReleaseConfiguration,
        ])

        // When
        try await generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        try assertProject(expectedConfigurations: ["CustomDebug", "CustomRelease", "Debug", "Release"])
        try assertTarget(expectedConfigurations: ["CustomDebug", "CustomRelease", "Debug", "Release"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        let customDebug = try extractWorkspaceSettings(configuration: "CustomDebug")
        let release = try extractWorkspaceSettings(configuration: "Release")
        let customRelease = try extractWorkspaceSettings(configuration: "CustomRelease")

        #expect(debug.contains("GCC_PREPROCESSOR_DEFINITIONS", "DEBUG=1") == true)
        #expect(customDebug.contains("GCC_PREPROCESSOR_DEFINITIONS", "DEBUG=1") == true)

        // These include a prefix space because $(inherited)
        #expect(debug.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", " DEBUG") == true)
        #expect(customDebug.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", " DEBUG") == true)
        #expect(release.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG") == false)
        #expect(customRelease.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG") == false)

        #expect(debug.contains("SWIFT_COMPILATION_MODE", "singlefile") == true)
        #expect(customDebug.contains("SWIFT_COMPILATION_MODE", "singlefile") == true)
        #expect(release.contains("SWIFT_COMPILATION_MODE", "wholemodule") == true)
        #expect(customRelease.contains("SWIFT_COMPILATION_MODE", "wholemodule") == true)
    }

    // MARK: - Helpers

    private func generateWorkspace(projectSettings: Settings, targetSettings: Settings?) async throws {
        let models = try createModels(projectSettings: projectSettings, targetSettings: targetSettings)
        let subject = DescriptorGenerator()
        let writer = XcodeProjWriter()
        let linter = GraphLinter()
        let graphLoader = GraphLoader()

        let graph = try await graphLoader.loadWorkspace(
            workspace: models.workspace,
            projects: models.projects
        )
        let graphTraverser = GraphTraverser(graph: graph)
        try await linter.lint(graphTraverser: graphTraverser, configGeneratedProjectOptions: .test())
            .printAndThrowErrorsIfNeeded()
        let descriptor = try await subject.generateWorkspace(graphTraverser: graphTraverser)
        try await writer.write(workspace: descriptor)
    }

    private func setupTestProject() async throws {
        try await TuistTest.makeDirectories(["App/Sources"])
    }

    @discardableResult
    private func createFile(path relativePath: String, content: String) throws -> Path.AbsolutePath {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let absolutePath = temporaryPath.appending(try RelativePath(validating: relativePath))
        try FileHandler.shared.touch(absolutePath)
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: absolutePath.pathString))
        return absolutePath
    }

    private func createModels(projectSettings: Settings, targetSettings: Settings?) throws -> WorkspaceWithProjects {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let appTarget = try createAppTarget(settings: targetSettings)
        let project = createProject(
            path: try pathTo("App"),
            settings: projectSettings,
            targets: [appTarget],
            schemes: []
        )
        let workspace = try createWorkspace(path: temporaryPath, projects: ["App"])
        return WorkspaceWithProjects(workspace: workspace, projects: [project])
    }

    private func createWorkspace(path: Path.AbsolutePath, projects: [String]) throws -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "Workspace.xcworkspace"),
            name: "Workspace",
            projects: try projects.map { try pathTo($0) },
            generationOptions: .test(enableAutomaticXcodeSchemes: nil)
        )
    }

    private func createProject(
        path: Path.AbsolutePath,
        settings: Settings,
        targets: [Target],
        packages: [Package] = [],
        schemes: [Scheme]
    ) -> Project {
        Project(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "App.xcodeproj"),
            name: "App",
            organizationName: nil,
            classPrefix: nil,
            defaultKnownRegions: nil,
            developmentRegion: nil,
            options: .test(),
            settings: settings,
            filesGroup: .group(name: "Project"),
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: nil,
            additionalFiles: [],
            resourceSynthesizers: [],
            lastUpgradeCheck: nil,
            type: .local
        )
    }

    private func createAppTarget(settings: Settings?) throws -> Target {
        Target(
            name: "AppTarget",
            destinations: .iOS,
            product: .app,
            productName: "AppTarget",
            bundleId: "test.bundle",
            settings: settings,
            sources: [SourceFile(path: try pathTo("App/Sources/AppDelegate.swift"))],
            filesGroup: .group(name: "ProjectGroup")
        )
    }

    private func pathTo(_ relativePath: String) throws -> Path.AbsolutePath {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        return temporaryPath.appending(try RelativePath(validating: relativePath))
    }

    private func extractWorkspaceSettings(configuration: String) throws -> ExtractedBuildSettings {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        return try extractBuildSettings(path: .workspace(
            path: temporaryPath.appending(component: "Workspace.xcworkspace").pathString,
            scheme: "AppTarget",
            configuration: configuration
        ))
    }

    private func loadXcodeProj(_ relativePath: String) throws -> XcodeProj {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let appProjectPath = temporaryPath.appending(try RelativePath(validating: relativePath))
        return try XcodeProj(pathString: appProjectPath.pathString)
    }

    // MARK: - Assertions

    private func assertTarget(
        _ target: String = "AppTarget",
        expectedConfigurations: Set<String>
    ) throws {
        let proj: XcodeProj = try loadXcodeProj("App/App.xcodeproj")
        let nativeTarget = try #require(proj.pbxproj.nativeTargets.first(where: { $0.name == target }))
        let configurationNames = Set(nativeTarget.buildConfigurationList?.buildConfigurations.map(\.name) ?? [])
        #expect(configurationNames == expectedConfigurations)
    }

    private func assertProject(
        expectedConfigurations: Set<String>
    ) throws {
        let proj: XcodeProj = try loadXcodeProj("App/App.xcodeproj")
        let rootProject: PBXProject? = try proj.pbxproj.rootProject()
        let configurationNames = Set(rootProject?.buildConfigurationList?.buildConfigurations.map(\.name) ?? [])
        #expect(configurationNames == expectedConfigurations)
    }
}

private func extractBuildSettings(path: XcodePath) throws -> ExtractedBuildSettings {
    var arguments = [
        "/usr/bin/xcrun",
        "xcodebuild",
        path.argument,
        path.path,
        "-showBuildSettings",
        "-configuration",
        path.configuration,
    ]

    if let scheme = path.scheme {
        arguments.append("-scheme")
        arguments.append(scheme)
    }

    let rawBuildSettings = try Process.checkNonZeroExit(arguments: arguments)
    return ExtractedBuildSettings(rawBuildSettings: rawBuildSettings)
}

private struct ExtractedBuildSettings {
    let rawBuildSettings: String

    func contains(_ key: String, _ value: String) -> Bool {
        contains((key, value))
    }

    func containsKey(_ key: String) -> Bool {
        rawBuildSettings.contains(" \(key)) = ")
    }

    func contains(_ pair: (key: String, value: String)) -> Bool {
        rawBuildSettings.contains("\(pair.key) = \(pair.value)")
    }

    func contains(settings: [String: String]) -> Bool {
        settings.allSatisfy { contains($0) }
    }
}

private enum XcodePath {
    case project(path: String, configuration: String)
    case workspace(path: String, scheme: String, configuration: String)

    var path: String {
        switch self {
        case let .project(path: path, configuration: _):
            return path
        case let .workspace(path: path, scheme: _, configuration: _):
            return path
        }
    }

    var scheme: String? {
        switch self {
        case .project(path: _, configuration: _):
            return nil
        case let .workspace(path: _, scheme: scheme, configuration: _):
            return scheme
        }
    }

    var configuration: String {
        switch self {
        case let .project(path: _, configuration: configuration):
            return configuration
        case let .workspace(path: _, scheme: _, configuration: configuration):
            return configuration
        }
    }

    var argument: String {
        switch self {
        case .project(path: _):
            return "-project"
        case .workspace(path: _, scheme: _, configuration: _):
            return "-workspace"
        }
    }
}
