import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoaderTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class MultipleConfigurationsIntegrationTests: TuistUnitTestCase {
    override func setUp() {
        super.setUp()
        do {
            system.swiftVersionStub = { "5.2" }
            xcodeController.selectedVersionStub = .success("11.0.0")
            try setupTestProject()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testGenerateThrowsLintingErrorWhenConfigurationsAreEmpty() throws {
        // Given
        let projectSettings = Settings(configurations: [:])
        let targetSettings: Settings? = nil

        // When / Then
        XCTAssertThrowsError(
            try generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)
        )
    }

    func testGenerateWhenSingleDebugConfigurationInProject() throws {
        // Given
        let projectSettings = Settings(
            base: ["A": "A"],
            configurations: [.debug: nil]
        )

        // When
        try generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        assertProject(expectedConfigurations: ["Debug"])
        assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        XCTAssertTrue(debug.contains("A", "A")) // from base
    }

    func testGenerateWhenConfigurationSettingsOverrideXCConfig() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        assertProject(expectedConfigurations: ["Debug"])
        assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        XCTAssertTrue(debug.contains("A", "A")) // from settings overriding .xcconfig
        XCTAssertTrue(debug.contains("B", "B_XCCONFIG")) // from .xcconfig
        XCTAssertTrue(debug.contains("C", "C")) // from settings
    }

    func testGenerateWhenConfigurationSettingsOverrideBase() throws {
        // Given
        let debugConfiguration = Configuration(settings: ["A": "A", "C": "C"])
        let projectSettings = Settings(
            base: ["A": "A_BASE", "B": "B_BASE"],
            configurations: [.debug: debugConfiguration]
        )

        // When
        try generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        assertProject(expectedConfigurations: ["Debug"])
        assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        XCTAssertTrue(debug.contains("A", "A")) // from configuration settings overriding base
        XCTAssertTrue(debug.contains("B", "B_BASE")) // from base
        XCTAssertTrue(debug.contains("C", "C")) // from settings
    }

    func testGenerateWhenBuildConfigurationWithCustomName() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        assertProject(expectedConfigurations: ["Custom", "Release"])
        assertTarget(expectedConfigurations: ["Custom", "Release"])

        let custom = try extractWorkspaceSettings(configuration: "Custom")
        XCTAssertTrue(custom.contains("A", "A")) // from custom settings overriding base
        XCTAssertTrue(custom.contains("B", "B_BASE")) // from base
        XCTAssertTrue(custom.contains("C", "C")) // from custom settings

        let release = try extractWorkspaceSettings(configuration: "Release")
        XCTAssertTrue(release.contains("A", "A_BASE")) // from base
        XCTAssertTrue(release.contains("B", "B_BASE")) // from base
        XCTAssertFalse(release.contains("C", "C")) // non-existing, only defined in Custom
    }

    func testGenerateWhenTargetSettingsOverrideTargetXCConfig() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        assertProject(expectedConfigurations: ["Debug"])
        assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Custom")
        XCTAssertTrue(debug.contains("A", "A")) // from target settings overriding target .xcconfig
        XCTAssertTrue(debug.contains("B", "B_XCCONFIG")) // from target .xcconfig
        XCTAssertTrue(debug.contains("C", "C")) // from target settings
    }

    func testGenerateWhenMultipleConfigurations() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        assertProject(expectedConfigurations: ["Debug", "ProjectRelease"])
        assertTarget(expectedConfigurations: ["Debug", "ProjectRelease", "Staging"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        XCTAssertTrue(debug.contains("A", "A_PROJECT_DEBUG")) // from project debug settings
        XCTAssertTrue(debug.contains("B", "B_TARGET_DEBUG")) // from target debug settings

        let release = try extractWorkspaceSettings(configuration: "ProjectRelease")
        XCTAssertTrue(release.contains("A", "A_PROJECT_RELEASE")) // from project debug settings
        XCTAssertTrue(release.contains("C", "C_PROJECT_RELEASE")) // from project debug settings
        XCTAssertFalse(release.containsKey("B")) // non-existing

        let staging = try extractWorkspaceSettings(configuration: "Staging")
        XCTAssertTrue(staging.contains("B", "B_TARGET_STAGING")) // from target staging settings
        XCTAssertFalse(staging.containsKey("A")) // non-existing
        XCTAssertFalse(staging.containsKey("C")) // non-existing
    }

    /**
     Exhaustive test to validate the priority of the particular settings:
     - project .xcconfig
     - project base
     - project configuration settings
     - target .xcconfig
     - target base
     - target configuraiton settings
     */
    func testGenerateWhenTargetSettingsOverrideProjectBaseSettingsAndXCConfig() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: targetSettings)

        // Then
        assertProject(expectedConfigurations: ["Debug"])
        assertTarget(expectedConfigurations: ["Debug"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        XCTAssertTrue(debug.contains("A", "A_PROJECT_XCCONFIG")) // from project .xcconfig
        XCTAssertTrue(debug.contains("B", "B_PROJECT_BASE")) // from project base
        XCTAssertTrue(debug.contains("C", "C_PROJECT")) // from project settings
        XCTAssertTrue(debug.contains("D", "D_TARGET_XCCONFIG")) // from target .xcconfig
        XCTAssertTrue(debug.contains("E", "E_TARGET_BASE")) // from target base
        XCTAssertTrue(debug.contains("F", "F_TARGET")) // from target settings
        XCTAssertTrue(debug.contains("PROJECT_XCCONFIG", "YES")) // from project .xcconfig
        XCTAssertTrue(debug.contains("PROJECT_BASE", "YES")) // from project base
        XCTAssertTrue(debug.contains("PROJECT", "YES")) // from project settings
        XCTAssertTrue(debug.contains("TARGET_XCCONFIG", "YES")) // from target .xcconfig
        XCTAssertTrue(debug.contains("TARGET_BASE", "YES")) // from target base
        XCTAssertTrue(debug.contains("TARGET", "YES")) // from target settings
    }

    func testGenerateWhenCustomConfigurations() throws {
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
        try generateWorkspace(projectSettings: projectSettings, targetSettings: nil)

        // Then
        assertProject(expectedConfigurations: ["CustomDebug", "CustomRelease", "Debug", "Release"])
        assertTarget(expectedConfigurations: ["CustomDebug", "CustomRelease", "Debug", "Release"])

        let debug = try extractWorkspaceSettings(configuration: "Debug")
        let customDebug = try extractWorkspaceSettings(configuration: "CustomDebug")
        let release = try extractWorkspaceSettings(configuration: "Release")
        let customRelease = try extractWorkspaceSettings(configuration: "CustomRelease")

        XCTAssertTrue(debug.contains("GCC_PREPROCESSOR_DEFINITIONS", "DEBUG=1"))
        XCTAssertTrue(customDebug.contains("GCC_PREPROCESSOR_DEFINITIONS", "DEBUG=1"))

        XCTAssertTrue(debug.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"))
        XCTAssertTrue(customDebug.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"))
        XCTAssertFalse(release.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"))
        XCTAssertFalse(customRelease.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"))

        XCTAssertTrue(debug.contains("SWIFT_COMPILATION_MODE", "singlefile"))
        XCTAssertTrue(customDebug.contains("SWIFT_COMPILATION_MODE", "singlefile"))
        XCTAssertTrue(release.contains("SWIFT_COMPILATION_MODE", "wholemodule"))
        XCTAssertTrue(customRelease.contains("SWIFT_COMPILATION_MODE", "wholemodule"))
    }

    // MARK: - Helpers

    private func generateWorkspace(projectSettings: Settings, targetSettings: Settings?) throws {
        let models = try createModels(projectSettings: projectSettings, targetSettings: targetSettings)
        let subject = DescriptorGenerator()
        let writer = XcodeProjWriter()
        let linter = GraphLinter()
        let graphLoader = GraphLoader()

        let graph = try graphLoader.loadWorkspace(workspace: models.workspace, projects: models.projects)
        let graphTraverser = GraphTraverser(graph: graph)
        try linter.lint(graphTraverser: graphTraverser).printAndThrowIfNeeded()
        let descriptor = try subject.generateWorkspace(graphTraverser: graphTraverser)
        try writer.write(workspace: descriptor)
    }

    private func setupTestProject() throws {
        try createFolders(["App/Sources"])
    }

    @discardableResult
    private func createFile(path relativePath: String, content: String) throws -> AbsolutePath {
        let temporaryPath = try temporaryPath()
        let absolutePath = temporaryPath.appending(RelativePath(relativePath))
        try FileHandler.shared.touch(absolutePath)
        try content.data(using: .utf8)!.write(to: URL(fileURLWithPath: absolutePath.pathString))
        return absolutePath
    }

    private func createModels(projectSettings: Settings, targetSettings: Settings?) throws -> WorkspaceWithProjects {
        let temporaryPath = try temporaryPath()
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

    private func createConfig() -> Config {
        Config(
            compatibleXcodeVersions: .all,
            cloud: nil,
            cache: .default,
            swiftVersion: nil,
            plugins: [],
            generationOptions: .test(),
            path: nil
        )
    }

    private func createWorkspace(path: AbsolutePath, projects: [String]) throws -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "Workspace.xcworkspace"),
            name: "Workspace",
            projects: try projects.map { try pathTo($0) },
            generationOptions: .test(enableAutomaticXcodeSchemes: nil)
        )
    }

    private func createProject(
        path: AbsolutePath,
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
            isExternal: false
        )
    }

    private func createAppTarget(settings: Settings?) throws -> Target {
        Target(
            name: "AppTarget",
            platform: .iOS,
            product: .app,
            productName: "AppTarget",
            bundleId: "test.bundle",
            settings: settings,
            sources: [SourceFile(path: try pathTo("App/Sources/AppDelegate.swift"))],
            filesGroup: .group(name: "ProjectGroup")
        )
    }

    private func pathTo(_ relativePath: String) throws -> AbsolutePath {
        let temporaryPath = try temporaryPath()
        return temporaryPath.appending(RelativePath(relativePath))
    }

    private func extractWorkspaceSettings(configuration: String) throws -> ExtractedBuildSettings {
        let temporaryPath = try temporaryPath()
        return try extractBuildSettings(path: .workspace(
            path: temporaryPath.appending(component: "Workspace.xcworkspace").pathString,
            scheme: "AppTarget",
            configuration: configuration
        ))
    }

    private func loadXcodeProj(_ relativePath: String) throws -> XcodeProj {
        let temporaryPath = try temporaryPath()
        let appProjectPath = temporaryPath.appending(RelativePath(relativePath))
        return try XcodeProj(pathString: appProjectPath.pathString)
    }

    // MARK: - Assertions

    private func assertTarget(
        _ target: String = "AppTarget",
        expectedConfigurations: Set<String>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let proj: XcodeProj
        do {
            proj = try loadXcodeProj("App/App.xcodeproj")
        } catch {
            XCTFail(error.localizedDescription, file: file, line: line)
            return
        }

        guard let nativeTarget = proj.pbxproj.nativeTargets.first(where: { $0.name == target }) else {
            XCTFail("Target \(target) not found", file: file, line: line)
            return
        }

        let configurationNames = Set(nativeTarget.buildConfigurationList?.buildConfigurations.map(\.name) ?? [])
        XCTAssertEqual(configurationNames, expectedConfigurations, file: file, line: line)
    }

    private func assertProject(
        expectedConfigurations: Set<String>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let proj: XcodeProj
        let rootProject: PBXProject?
        do {
            proj = try loadXcodeProj("App/App.xcodeproj")
            rootProject = try proj.pbxproj.rootProject()
        } catch {
            XCTFail(error.localizedDescription, file: file, line: line)
            return
        }

        let configurationNames = Set(rootProject?.buildConfigurationList?.buildConfigurations.map(\.name) ?? [])
        XCTAssertEqual(configurationNames, expectedConfigurations, file: file, line: line)
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

    let rawBuildSettings = try TSCBasic.Process.checkNonZeroExit(arguments: arguments)
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
