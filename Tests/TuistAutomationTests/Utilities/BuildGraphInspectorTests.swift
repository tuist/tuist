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
        subject = nil
        super.tearDown()
    }

    func test_allTestPlans() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan1 = TestPlan(
            path: path.appending(component: "Test1.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
            ],
            isDefault: true
        )
        let testPlan2 = TestPlan(
            path: path.appending(component: "Test2.testplan"),
            testTargets: [
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: false
        )
        let scheme1 = Scheme.test(
            testAction: .test(
                testPlans: [testPlan1]
            )
        )
        let scheme2 = Scheme.test(
            testAction: .test(
                testPlans: [testPlan2]
            )
        )

        let project = Project.test(path: projectPath, schemes: [scheme1, scheme2])
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [
                target1.name: target1,
                target2.name: target2,
            ]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let testPlans = graphTraverser.allTestPlans()

        // Then
        XCTAssertEqual(testPlans, Set([testPlan1, testPlan2]))
    }

    func test_buildArguments_when_skipSigning() throws {
        // Given
        let target = Target.test(platform: .iOS)

        // When
        let got = subject.buildArguments(project: .test(), target: target, configuration: nil, skipSigning: true)

        // Then
        XCTAssertEqual(got, [
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
        let got = subject.buildArguments(
            project: .test(settings: settings),
            target: target,
            configuration: "Release",
            skipSigning: false
        )

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
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [target.name: target]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableTarget(scheme: scheme, graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target)
    }

    func test_testableTarget_whenNoTestActions_returnsNil() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")

        let scheme = Scheme.test()
        let project = Project.test(path: projectPath)
        let graph = Graph.test(projects: [projectPath: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertNil(got)
    }

    func test_testableTarget_whenNoTestPlan_returnsFirstTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "Test")
        let targetReference = TargetReference(projectPath: projectPath, name: target.name)

        let scheme = Scheme.test(
            testAction: .test(
                targets: [TestableTarget(target: targetReference)]
            )
        )
        let project = Project.test(path: projectPath)
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [target.name: target]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: nil,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target)
    }

    func test_testableTarget_withTestPlan_noFilters_returnsFirstEnabledTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(path: projectPath)
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [
                target1.name: target1,
                target2.name: target2,
            ]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [],
            skipTestTargets: [],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersIncluded_returnsMachingTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(path: projectPath)
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [
                target1.name: target1,
                target2.name: target2,
            ]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [TestIdentifier(target: targetReference2.name)],
            skipTestTargets: [],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersExcluded_returnsMachingTarget() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: false),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(path: projectPath)
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [
                target1.name: target1,
                target2.name: target2,
            ]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [],
            skipTestTargets: [TestIdentifier(target: targetReference1.name)],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertEqual(got?.project, project)
        XCTAssertEqual(got?.target, target2)
    }

    func test_testableTarget_withTestPlan_filtersIncludedDisabledTarget_returnsNil() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let target1 = Target.test(name: "Test1")
        let targetReference1 = TargetReference(projectPath: projectPath, name: target1.name)
        let target2 = Target.test(name: "Test2")
        let targetReference2 = TargetReference(projectPath: projectPath, name: target2.name)

        let testPlan = TestPlan(
            path: path.appending(component: "Test.testplan"),
            testTargets: [
                TestableTarget(target: targetReference1, skipped: true),
                TestableTarget(target: targetReference2, skipped: false),
            ],
            isDefault: true
        )
        let scheme = Scheme.test(
            testAction: .test(
                testPlans: [testPlan]
            )
        )
        let project = Project.test(path: projectPath)
        let graph = Graph.test(
            projects: [projectPath: project],
            targets: [projectPath: [
                target1.name: target1,
                target2.name: target2,
            ]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.testableTarget(
            scheme: scheme,
            testPlan: testPlan.name,
            testTargets: [TestIdentifier(target: targetReference1.name)],
            skipTestTargets: [],
            graphTraverser: graphTraverser
        )

        // Then
        XCTAssertNil(got)
    }

    func test_buildableSchemes() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project.xcodeproj")
        let coreProjectPath = path.appending(component: "CoreProject.xcodeproj")
        let coreScheme = Scheme.test(
            name: "Core",
            buildAction: .test(targets: [.init(projectPath: coreProjectPath, name: "Core")])
        )
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
                coreProject.path: coreProject,
                kitProject.path: kitProject,
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableSchemes(graphTraverser: graphTraverser)

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
        let coreGraphTarget = GraphTarget.test(
            target: coreTarget,
            project: coreProject
        )
        let coreTestsTarget = Target.test(
            name: "CoreTests",
            product: .unitTests,
            dependencies: [.target(name: "Core")]
        )
        let coreTestsGraphTarget = GraphTarget.test(
            target: coreTestsTarget,
            project: coreProject
        )
        let kitTarget = Target.test(name: "Kit", dependencies: [.target(name: "Core")])
        let kitProject = Project.test(
            path: projectPath,
            schemes: [kitScheme, kitTestsScheme]
        )
        let kitGraphTarget = GraphTarget.test(
            target: kitTarget,
            project: kitProject
        )
        let kitTestsTarget = Target.test(
            name: "KitTests",
            product: .unitTests,
            dependencies: [.target(name: "Kit")]
        )
        let kitTestsGraphTarget = GraphTarget.test(
            target: kitTestsTarget,
            project: kitProject
        )
        let graph = Graph.test(
            projects: [
                kitProject.path: kitProject,
                coreProject.path: coreProject,
            ],
            targets: [
                projectPath: [
                    kitGraphTarget.target.name: kitGraphTarget.target,
                    kitTestsGraphTarget.target.name: kitTestsGraphTarget.target,
                ],
                coreProjectPath: [
                    coreGraphTarget.target.name: coreGraphTarget.target,
                    coreTestsGraphTarget.target.name: coreTestsGraphTarget.target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testSchemes(graphTraverser: graphTraverser)

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
        let coreTestPlan = TestPlan(
            path: projectPath,
            testTargets: [TestableTarget(
                target: TargetReference(projectPath: projectPath, name: coreTarget.name),
                skipped: false
            )],
            isDefault: true
        )
        let coreTestPlanScheme = Scheme.test(
            name: "TestPlan",
            testAction: .test(
                testPlans: [coreTestPlan]
            )
        )
        let coreTestPlanTestsScheme = Scheme(
            name: "TestPlanTests",
            testAction: .test(
                testPlans: [coreTestPlan]
            )
        )
        let coreProject = Project.test(
            path: coreProjectPath,
            schemes: [coreScheme, coreTestsScheme, coreTestPlanScheme, coreTestPlanTestsScheme]
        )
        let coreGraphTarget = GraphTarget.test(
            target: coreTarget,
            project: coreProject
        )
        let graph = Graph.test(
            projects: [
                coreProject.path: coreProject,
            ],
            targets: [
                coreProject.path: [
                    coreGraphTarget.target.name: coreGraphTarget.target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.testableSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                coreScheme,
                coreTestsScheme,
                coreTestPlanScheme,
                coreTestPlanTestsScheme,
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

        let projectBPath = path.appending(component: "ProjectB.xcodeproj")
        let schemeB = Scheme.test(buildAction: .test(targets: [.init(projectPath: projectBPath, name: "B")]))
        let projectB = Project.test(path: projectBPath, schemes: [schemeB])
        let targetB = Target.test(name: "B")

        let graph = Graph.test(
            workspace: Workspace.test(projects: [projectA.path]),
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [projectAPath: [targetA.name: targetA], projectBPath: [targetB.name: targetB]]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.buildableEntrySchemes(graphTraverser: graphTraverser)

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
                    .test(name: "WorkspaceName-Workspace-iOS"),
                    .test(name: "WorkspaceName-Workspace-macOS"),
                ]
            )
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.workspaceSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Workspace-iOS"),
                .test(name: "WorkspaceName-Workspace-macOS"),
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
                    .test(name: "WorkspaceName-Workspace"),
                ]
            )
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.workspaceSchemes(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(
            got,
            [
                .test(name: "WorkspaceName-Workspace"),
            ]
        )
    }
}
