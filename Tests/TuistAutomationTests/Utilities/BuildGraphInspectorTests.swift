import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class BuildGraphInspectorTests: TuistUnitTestCase {
    var subject: BuildGraphInspector!

    override func setUp() {
        super.setUp()
        subject = BuildGraphInspector()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_buildArguments_when_macOS() throws {
        // Given
        let target = Target.test(platform: .macOS)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: false)

        // Then
        XCTAssertEqual(got, [
            .sdk(Platform.macOS.xcodeDeviceSDK),
        ])
    }

    func test_buildArguments_when_iOS() throws {
        // Given
        let target = Target.test(platform: .iOS)
        let iosSimulatorSDK = try XCTUnwrap(Platform.iOS.xcodeSimulatorSDK)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: false)

        // Then
        XCTAssertEqual(got, [
            .sdk(iosSimulatorSDK),
        ])
    }

    func test_buildArguments_when_watchOS() throws {
        // Given
        let target = Target.test(platform: .watchOS)
        let watchosSimulatorSDK = try XCTUnwrap(Platform.watchOS.xcodeSimulatorSDK)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: false)

        // Then
        XCTAssertEqual(got, [
            .sdk(watchosSimulatorSDK),
        ])
    }

    func test_buildArguments_when_tvOS() throws {
        // Given
        let target = Target.test(platform: .tvOS)
        let tvosSimulatorSDK = try XCTUnwrap(Platform.tvOS.xcodeSimulatorSDK)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: false)

        // Then
        XCTAssertEqual(got, [
            .sdk(tvosSimulatorSDK),
        ])
    }

    func test_buildArguments_when_skipSigning() throws {
        // Given
        let target = Target.test(platform: .iOS)
        let iosSimulatorSDK = try XCTUnwrap(Platform.iOS.xcodeSimulatorSDK)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: true)

        // Then
        XCTAssertEqual(got, [
            .sdk(iosSimulatorSDK),
            .xcarg("CODE_SIGN_IDENTITY", ""),
            .xcarg("CODE_SIGNING_REQUIRED", "NO"),
            .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
            .xcarg("CODE_SIGNING_ALLOWED", "NO"),
        ])
    }

    func test_buildArguments_when_theGivenConfigurationExists() throws {
        // Given
        let settings = Settings.test(base: [:], debug: .test(), release: .test())
        let target = Target.test(settings: settings)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: "Release", skipSigning: false)

        // Then
        XCTAssertTrue(got.contains(.configuration("Release")))
    }

    func test_buildArguments_when_theGivenConfigurationExistsInTheProject() throws {
        // Given
        let settings = Settings.test(base: [:], debug: .test(), release: .test())
        let target = Target.test(settings: nil)

        // When
        let got = subject.buildArguments(project: .test(settings: settings), target: target, configuration: "Release", skipSigning: false)

        // Then
        XCTAssertTrue(got.contains(.configuration("Release")))
    }

    func test_buildArguments_when_theGivenConfigurationDoesntExist() throws {
        // Given
        let settings = Settings.test(base: [:], configurations: [:])
        let target = Target.test(settings: settings)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: "Release", skipSigning: false)

        // Then
        XCTAssertFalse(got.contains(.configuration("Release")))
    }

    func test_buildableTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectPath, name: "Core")]))
        let target = Target.test(name: "Core")
        let project = Project.test(path: projectPath)
        let targetNode = TargetNode.test(project: project,
                                         target: target)
        let graph = Graph.test(targets: [projectPath: [targetNode]])

        // When
        let got = subject.buildableTarget(scheme: scheme, graph: graph)

        // Then
        XCTAssertEqual(got?.0, project)
        XCTAssertEqual(got?.1, target)
    }

    func test_buildableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(name: "Core", buildAction: .test(targets: [.init(projectPath: coreProjectPath, name: "Core")]))
        let kitScheme = Scheme.test(name: "Kit", buildAction: .test(targets: [.init(projectPath: projectPath, name: "Kit")]))
        let coreProject = Project.test(path: coreProjectPath, schemes: [coreScheme])
        let kitProject = Project.test(path: projectPath, schemes: [kitScheme])
        let workspaceScheme = Scheme.test(
            name: "Workspace-Scheme",
            buildAction: .test(
                targets: [
                    .init(projectPath: coreProjectPath, name: "Core"),
                    .init(projectPath: projectPath, name: "Kit"),
                ]
            )
        )
        let workspace = Workspace.test(schemes: [workspaceScheme])
        let graph = Graph.test(
            workspace: workspace,
            projects: [
                coreProject,
                kitProject,
            ]
        )

        // When
        let got = subject.buildableSchemes(graph: graph)

        // Then
        XCTAssertEqual(
            got,
            [
                coreScheme,
                kitScheme,
                workspaceScheme,
            ]
        )
    }

    func test_testSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTestsScheme = Scheme(
            name: "CoreTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let kitScheme = Scheme.test(
            name: "Kit",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "KitTests"))]
            )
        )
        let kitTestsScheme = Scheme(
            name: "KitTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "KitTests"))]
            )
        )
        let coreTarget = Target.test(name: "Core")
        let coreProject = Project.test(
            path: coreProjectPath,
            schemes: [coreScheme, coreTestsScheme]
        )
        let coreTargetNode = TargetNode.test(
            project: coreProject,
            target: coreTarget
        )
        let coreTestsTarget = Target.test(
            name: "CoreTests",
            product: .unitTests,
            dependencies: [.target(name: "Core")]
        )
        let coreTestsTargetNode = TargetNode.test(
            project: coreProject,
            target: coreTestsTarget
        )
        let kitTarget = Target.test(name: "Kit", dependencies: [.target(name: "Core")])
        let kitProject = Project.test(
            path: projectPath,
            schemes: [kitScheme, kitTestsScheme]
        )
        let kitTargetNode = TargetNode.test(
            project: kitProject,
            target: kitTarget
        )
        let kitTestsTarget = Target.test(
            name: "KitTests",
            product: .unitTests,
            dependencies: [.target(name: "Kit")]
        )
        let kitTestsTargetNode = TargetNode.test(
            project: kitProject,
            target: kitTestsTarget
        )
        let graph = Graph.test(
            entryNodes: [kitTargetNode],
            targets: [
                projectPath: [kitTargetNode, kitTestsTargetNode],
                coreProjectPath: [coreTargetNode, coreTestsTargetNode],
            ]
        )

        // When
        let got = subject.testSchemes(graph: graph)

        // Then
        XCTAssertEqual(
            got,
            [
                coreTestsScheme,
                kitTestsScheme,
            ]
        )
    }

    func test_testableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTestsScheme = Scheme(
            name: "CoreTests",
            testAction: .test(
                targets: [.init(target: .init(projectPath: projectPath, name: "CoreTests"))]
            )
        )
        let coreTarget = Target.test(name: "Core")
        let coreProject = Project.test(
            path: coreProjectPath,
            schemes: [coreScheme, coreTestsScheme]
        )
        let coreTargetNode = TargetNode.test(
            project: coreProject,
            target: coreTarget
        )
        let graph = Graph.test(
            entryNodes: [coreTargetNode],
            projects: [
                coreProject,
            ]
        )

        // When
        let got = subject.testableSchemes(graph: graph)

        // Then
        XCTAssertEqual(
            got,
            [
                coreScheme,
                coreTestsScheme,
            ]
        )
    }

    func test_buildableEntrySchemes_only_includes_entryTargets() throws {
        // Given
        let path = try temporaryPath()

        let projectAPath = path.appending(component: "ProjectA.xcodeproj")
        let schemeA = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectAPath, name: "A")]))
        let projectA = Project.test(path: projectAPath, schemes: [schemeA])
        let targetA = Target.test(name: "A")
        let targetANode = TargetNode.test(project: projectA,
                                          target: targetA)

        let projectBPath = path.appending(component: "ProjectB.xcodeproj")
        let schemeB = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectBPath, name: "B")]))
        let projectB = Project.test(path: projectBPath, schemes: [schemeB])
        let targetB = Target.test(name: "B")
        let targetBNode = TargetNode.test(project: projectB,
                                          target: targetB)

        let graph = Graph.test(entryNodes: [targetANode],
                               targets: [projectAPath: [targetANode], projectBPath: [targetBNode]])

        // When
        let got = subject.buildableEntrySchemes(graph: graph)

        // Then
        XCTAssertEqual(got, [schemeA])
    }

    func test_workspacePath() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)
        try FileHandler.shared.touch(workspacePath.appending(component: Constants.tuistGeneratedFileName))

        // When
        let got = try subject.workspacePath(directory: path)

        // Then
        XCTAssertEqual(got, workspacePath)
    }

    func test_workspacePath_when_no_tuist_workspace_is_present() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)

        // When
        let got = try subject.workspacePath(directory: path)

        // Then
        XCTAssertNil(got)
    }

    func test_workspacePath_when_multiple_workspaces_are_present() throws {
        // Given
        let path = try temporaryPath()
        let nonTuistWorkspacePath = path.appending(components: "SPM.xcworkspace")
        try FileHandler.shared.createFolder(nonTuistWorkspacePath)
        let workspacePath = path.appending(component: "TuistApp.xcworkspace")
        try FileHandler.shared.createFolder(workspacePath)
        try FileHandler.shared.touch(workspacePath.appending(component: Constants.tuistGeneratedFileName))

        // When
        let got = try subject.workspacePath(directory: path)

        // Then
        XCTAssertEqual(got, workspacePath)
    }

    func test_projectSchemes_when_multiple_platforms() {
        // Given
        let graph: Graph = .test(
            workspace: .test(
                name: "WorkspaceName",
                schemes: [
                    .test(name: "WorkspaceName"),
                    .test(name: "WorkspaceName-Project-iOS"),
                    .test(name: "WorkspaceName-Project-macOS"),
                ]
            )
        )

        // When
        let got = subject.projectSchemes(graph: graph)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Project-iOS"),
                .test(name: "WorkspaceName-Project-macOS"),
            ]
        )
    }

    func test_projectSchemes_when_single_platform() {
        // Given
        let graph: Graph = .test(
            workspace: .test(
                name: "WorkspaceName",
                schemes: [
                    .test(name: "WorkspaceName"),
                    .test(name: "WorkspaceName-Project"),
                ]
            )
        )

        // When
        let got = subject.projectSchemes(graph: graph)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Project"),
            ]
        )
    }
}
