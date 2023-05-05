import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupportTesting

final class SchemeDescriptorsGeneratorTests: XCTestCase {
    var subject: SchemeDescriptorsGenerator!

    override func setUp() {
        super.setUp()
        subject = SchemeDescriptorsGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Build Action Tests

    func test_schemeBuildAction_whenSingleProject() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]))

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: [
                xcodeProjPath: generatedProject(targets: targets, projectPath: "\(xcodeProjPath)"),
            ]
        )

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildActionEntries.count, 1)
        let entry = try XCTUnwrap(result.buildActionEntries.first)
        let buildableReference = entry.buildableReference
        XCTAssertEqual(entry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(buildableReference.referencedContainer, "container:Projects/Project/Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "App.app")
        XCTAssertEqual(buildableReference.blueprintName, "App")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(result.parallelizeBuild, true)
        XCTAssertEqual(result.buildImplicitDependencies, true)
    }

    func test_schemeBuildAction_whenSingleProjectAndXcodeProjPathDiffers() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let xcodeProjPath = try AbsolutePath(validating: "/differentpath/Workspace/project.xcodeproj")
        let scheme = Scheme.test(buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]))

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/differentpath/Workspace"),
            generatedProjects: [
                xcodeProjPath: generatedProject(targets: targets, projectPath: xcodeProjPath.pathString),
            ]
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildActionEntries.count, 1)
        let entry = try XCTUnwrap(result.buildActionEntries.first)
        let buildableReference = entry.buildableReference
        XCTAssertEqual(entry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "App.app")
        XCTAssertEqual(buildableReference.blueprintName, "App")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(result.parallelizeBuild, true)
        XCTAssertEqual(result.buildImplicitDependencies, true)
    }

    func test_schemeBuildAction_whenMultipleProject() throws {
        // Given
        let projectAPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/ProjectA")
        let xcodeProjAPath = projectAPath.appending(component: "project.xcodeproj")
        let projectBPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/ProjectB")
        let xcodeProjBPath = projectBPath.appending(component: "project.xcodeproj")

        let buildAction = BuildAction(targets: [
            TargetReference(projectPath: projectAPath, name: "FrameworkA"),
            TargetReference(projectPath: projectBPath, name: "FrameworkB"),
        ])
        let scheme = Scheme.test(buildAction: buildAction)

        let frameworkA = Target.test(name: "FrameworkA", product: .staticFramework)
        let frameworkB = Target.test(name: "FrameworkB", product: .staticFramework)
        let targets = [frameworkA, frameworkB]

        let projectA = Project.test(
            path: projectAPath,
            xcodeProjPath: xcodeProjAPath
        )
        let projectB = Project.test(
            path: projectBPath,
            xcodeProjPath: xcodeProjBPath
        )
        let graph = Graph.test(
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
            ],
            targets: [
                projectA.path: [
                    frameworkA.name: frameworkA,
                ],
                projectB.path: [
                    frameworkB.name: frameworkB,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: [
                xcodeProjAPath: generatedProject(targets: targets, projectPath: "\(projectAPath)/project.xcodeproj"),
                xcodeProjBPath: generatedProject(targets: targets, projectPath: "\(projectBPath)/project.xcodeproj"),
            ]
        )

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildActionEntries.count, 2)

        let firstEntry = try XCTUnwrap(result.buildActionEntries[0])
        let firstBuildableReference = firstEntry.buildableReference
        XCTAssertEqual(firstEntry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        let secondEntry = try XCTUnwrap(result.buildActionEntries[1])
        let secondBuildableReference = secondEntry.buildableReference
        XCTAssertEqual(secondEntry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(firstBuildableReference.referencedContainer, "container:Projects/ProjectA/project.xcodeproj")
        XCTAssertEqual(firstBuildableReference.buildableName, "FrameworkA.framework")
        XCTAssertEqual(firstBuildableReference.blueprintName, "FrameworkA")
        XCTAssertEqual(firstBuildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(secondBuildableReference.referencedContainer, "container:Projects/ProjectB/project.xcodeproj")
        XCTAssertEqual(secondBuildableReference.buildableName, "FrameworkB.framework")
        XCTAssertEqual(secondBuildableReference.blueprintName, "FrameworkB")
        XCTAssertEqual(secondBuildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(result.parallelizeBuild, true)
        XCTAssertEqual(result.buildImplicitDependencies, true)
    }

    func test_schemeBuildAction_with_executionAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "App", product: .app)

        let preAction = ExecutionAction(
            title: "Pre Action",
            scriptText: "echo Pre Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )
        let postAction = ExecutionAction(
            title: "Post Action",
            scriptText: "echo Post Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )
        let buildAction = BuildAction.test(
            targets: [TargetReference(projectPath: projectPath, name: "App")],
            preActions: [preAction],
            postActions: [postAction]
        )

        let scheme = Scheme.test(name: "App", shared: true, buildAction: buildAction)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        // Pre Action
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")
        XCTAssertEqual(got?.preActions.first?.shellToInvoke, "/bin/sh")

        let preBuildableReference = got?.preActions.first?.environmentBuildable

        XCTAssertEqual(preBuildableReference?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(preBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(preBuildableReference?.blueprintName, "App")
        XCTAssertEqual(preBuildableReference?.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")
        XCTAssertEqual(got?.postActions.first?.shellToInvoke, "/bin/sh")

        let postBuildableReference = got?.postActions.first?.environmentBuildable

        XCTAssertEqual(postBuildableReference?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(postBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(postBuildableReference?.blueprintName, "App")
        XCTAssertEqual(postBuildableReference?.buildableIdentifier, "primary")
    }

    func test_buildAction_runPostActionsOnFailure() throws {
        // Given
        let schemeA = Scheme(
            name: "SchemeA",
            buildAction: BuildAction(
                targets: [],
                runPostActionsOnFailure: true
            )
        )
        let schemeB = Scheme(
            name: "SchemeB",
            buildAction: BuildAction(
                targets: [],
                runPostActionsOnFailure: false
            )
        )
        let project = Project.test(schemes: [schemeA, schemeB])
        let generatedProject = generatedProject(targets: project.targets)
        let graph = Graph.test(projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let schemeDescriptors = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject,
            graphTraverser: graphTraverser
        )

        // Then
        // `runPostActionsOnFailure` is omitted when not enabled (Xcode automatically removes it)
        let buildActions = schemeDescriptors.compactMap(\.xcScheme.buildAction)
        XCTAssertEqual(buildActions.map(\.runPostActionsOnFailure), [
            true,
            nil,
        ])
    }

    func test_buildAction_workspaceScheme_executionActionTargetContainerPath() throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/workspace")
        let projectPath = workspacePath.appending(components: ["Projects", "Project"])
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "App", product: .app)

        let preAction = ExecutionAction(
            title: "Pre Action",
            scriptText: "echo Pre Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: nil
        )
        let buildAction = BuildAction.test(
            targets: [TargetReference(projectPath: projectPath, name: "App")],
            preActions: [preAction],
            postActions: []
        )

        let scheme = Scheme.test(name: "App", shared: true, buildAction: buildAction)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: workspacePath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        // Pre Action

        let preBuildableReference = try XCTUnwrap(got?.preActions.first?.environmentBuildable)

        XCTAssertEqual(preBuildableReference.referencedContainer, "container:Projects/Project/Project.xcodeproj")
        XCTAssertEqual(preBuildableReference.buildableName, "App.app")
        XCTAssertEqual(preBuildableReference.blueprintName, "App")
        XCTAssertEqual(preBuildableReference.buildableIdentifier, "primary")
    }

    // MARK: - Test Action Tests

    func test_schemeTestAction_when_testsTarget() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
            arguments: nil
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: generatedProjects
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(result.macroExpansion)
        let testable = try XCTUnwrap(result.testables.first)
        let buildableReference = testable.buildableReference

        XCTAssertEqual(testable.skipped, false)
        XCTAssertEqual(buildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(buildableReference.blueprintName, "AppTests")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")
    }

    func test_schemeTestAction_with_expandVariable() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
            arguments: nil,
            expandVariableFromTarget: TargetReference(projectPath: project.path, name: "App")
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: generatedProjects
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        let testable = try XCTUnwrap(result.testables.first)
        let buildableReference = testable.buildableReference

        XCTAssertEqual(result.macroExpansion?.buildableName, "App.app")
        XCTAssertEqual(result.macroExpansion?.blueprintName, "App")
        XCTAssertEqual(result.macroExpansion?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(result.macroExpansion?.buildableIdentifier, "primary")

        XCTAssertEqual(testable.skipped, false)

        XCTAssertEqual(buildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(buildableReference.blueprintName, "AppTests")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")
    }

    func test_schemeTestAction_with_codeCoverageTargets() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
            coverage: true,
            codeCoverageTargets: [TargetReference(projectPath: projectPath, name: "App")]
        )
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])

        let scheme = Scheme.test(name: "AppTests", shared: true, buildAction: buildAction, testAction: testAction)

        let project = Project.test(path: projectPath, targets: [target, testTarget])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        let codeCoverageTargetsBuildableReference = try XCTUnwrap(result.codeCoverageTargets)
        XCTAssertEqual(result.onlyGenerateCoverageForSpecifiedTargets, true)
        XCTAssertEqual(codeCoverageTargetsBuildableReference.count, 1)
        XCTAssertEqual(codeCoverageTargetsBuildableReference.first?.buildableName, "App.app")
    }

    func test_schemeTestAction_when_notTestsTarget() throws {
        // Given
        let scheme = Scheme.test()
        let project = Project.test()
        let generatedProject = GeneratedProject.test()
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: [project.path: generatedProject]
        )

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, false)
        XCTAssertNil(result.macroExpansion)
        XCTAssertEqual(result.testables.count, 0)
    }

    func test_schemeTestAction_when_usingTestPlans() throws {
        // Given
        let project = Project.test()
        let planPath = try AbsolutePath(validating: "folder/Plan.xctestplan", relativeTo: project.path)
        let planList = [TestPlan(path: planPath, isDefault: true)]
        let scheme = Scheme.test(testAction: TestAction.test(testPlans: planList))
        let generatedProject = GeneratedProject.test()
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: [project.path: generatedProject]
        )

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(result.testPlans?.count, 1)
        XCTAssertEqual(result.testPlans?.first?.reference, "container:folder/Plan.xctestplan")
    }

    func test_schemeTestAction_when_usingTestPlans_with_disabled_attachDebugger() throws {
        // Given
        let project = Project.test()
        let planPath = try AbsolutePath(validating: "folder/Plan.xctestplan", relativeTo: project.path)
        let planList = [TestPlan(path: planPath, isDefault: true)]
        let scheme = Scheme.test(testAction: TestAction.test(attachDebugger: false, testPlans: planList))
        let generatedProject = GeneratedProject.test()
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // Then
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: [project.path: generatedProject]
        )

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.IDEFoundation.Launcher.PosixSpawn")
        XCTAssertEqual(result.testPlans?.count, 1)
        XCTAssertEqual(result.testPlans?.first?.reference, "container:folder/Plan.xctestplan")
    }

    func test_schemeTestAction_with_testable_info() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testableTarget = TestableTarget(
            target: TargetReference(projectPath: project.path, name: "AppTests"),
            skipped: false,
            parallelizable: true,
            randomExecutionOrdering: true
        )
        let testAction = TestAction.test(targets: [testableTarget])
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: project.path, name: "App")])

        let scheme = Scheme.test(name: "AppTests", shared: true, buildAction: buildAction, testAction: testAction)
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")

        // Then
        let testableTargetReference = result.testables[0]
        XCTAssertEqual(testableTargetReference.skipped, false)
        XCTAssertEqual(testableTargetReference.parallelizable, true)
        XCTAssertEqual(testableTargetReference.randomExecutionOrdering, true)
    }

    func test_schemeTestAction_with_disabled_attachDebugger() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
            attachDebugger: false
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: generatedProjects
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.IDEFoundation.Launcher.PosixSpawn")
    }

    func test_schemeBuildAction() throws {
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
            arguments: nil
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                    testTarget.name: testTarget,
                ],
            ],
            dependencies: [
                .target(name: testTarget.name, path: project.path): [
                    .target(name: target.name, path: project.path),
                ],
            ]
        )

        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: generatedProjects
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(result.macroExpansion)
        let testable = try XCTUnwrap(result.testables.first)
        let buildableReference = testable.buildableReference

        XCTAssertEqual(testable.skipped, false)
        XCTAssertEqual(buildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(buildableReference.blueprintName, "AppTests")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")
    }

    func test_schemeTestAction_with_executionAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let preAction = ExecutionAction(
            title: "Pre Action",
            scriptText: "echo Pre Actions",
            target: TargetReference(projectPath: projectPath, name: "AppTests"),
            shellPath: "/bin/sh"
        )
        let postAction = ExecutionAction(
            title: "Post Action",
            scriptText: "echo Post Actions",
            target: TargetReference(projectPath: projectPath, name: "AppTests"),
            shellPath: "/bin/sh"
        )
        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
            preActions: [preAction],
            postActions: [postAction],
            language: "es",
            region: "ES"
        )

        let scheme = Scheme.test(name: "AppTests", shared: true, testAction: testAction)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(components: "Project.xcodeproj"),
            targets: [testTarget]
        )

        let generatedProjects = createGeneratedProjects(projects: [project])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    testTarget.name: testTarget,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeTestAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: generatedProjects
        )

        // Then
        // Pre Action
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.language, "es")
        XCTAssertEqual(result.region, "ES")
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")

        XCTAssertEqual(result.preActions.first?.title, "Pre Action")
        XCTAssertEqual(result.preActions.first?.scriptText, "echo Pre Actions")
        XCTAssertEqual(result.preActions.first?.shellToInvoke, "/bin/sh")

        let preBuildableReference = try XCTUnwrap(result.preActions.first?.environmentBuildable)

        XCTAssertEqual(preBuildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(preBuildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(preBuildableReference.blueprintName, "AppTests")
        XCTAssertEqual(preBuildableReference.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(result.postActions.first?.title, "Post Action")
        XCTAssertEqual(result.postActions.first?.scriptText, "echo Post Actions")
        XCTAssertEqual(result.postActions.first?.shellToInvoke, "/bin/sh")

        let postBuildableReference = try XCTUnwrap(result.postActions.first?.environmentBuildable)

        XCTAssertEqual(postBuildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(postBuildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(postBuildableReference.blueprintName, "AppTests")
        XCTAssertEqual(postBuildableReference.buildableIdentifier, "primary")
    }

    // MARK: - Launch Action Tests

    func test_schemeLaunchAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let environment = ["env1": "1", "env2": "2", "env3": "3", "env4": "4"]
        let launchArguments = [
            LaunchArgument(name: "arg1", isEnabled: true),
            LaunchArgument(name: "arg2", isEnabled: true),
            LaunchArgument(name: "arg3", isEnabled: false),
            LaunchArgument(name: "arg4", isEnabled: true),
        ]

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let runAction = RunAction.test(
            configurationName: "Release",
            customLLDBInitFile: "/somepath/Workspace/Projects/etc/path/to/lldbinit",
            executable: TargetReference(projectPath: projectPath, name: "App"),
            arguments: Arguments(environment: environment, launchArguments: launchArguments),
            options: .init(
                language: "pl",
                storeKitConfigurationPath: "/somepath/Workspace/Projects/Project/nested/configuration/configuration.storekit",
                simulatedLocation: .reference("New York, NY, USA"),
                enableGPUFrameCaptureMode: .metal
            )
        )

        let scheme = Scheme.test(buildAction: buildAction, runAction: runAction)

        let app = Target.test(name: "App", product: .app, environment: environment)

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [app]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertNil(result.macroExpansion)

        let buildableReference = try XCTUnwrap(result.runnable?.buildableReference)

        XCTAssertEqual(result.buildConfiguration, "Release")
        XCTAssertEqual(result.commandlineArguments, XCScheme.CommandLineArguments(arguments: [
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg1", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg2", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg3", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg4", enabled: true),
        ]))
        XCTAssertEqual(result.environmentVariables, [
            XCScheme.EnvironmentVariable(variable: "env1", value: "1", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env2", value: "2", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env3", value: "3", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env4", value: "4", enabled: true),
        ])
        XCTAssertNil(result.askForAppToLaunch)
        XCTAssertNil(result.launchAutomaticallySubstyle)
        XCTAssertEqual(result.customLLDBInitFile, "$(SRCROOT)/../etc/path/to/lldbinit")
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertEqual(buildableReference.referencedContainer, "container:Projects/Project/Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "App.app")
        XCTAssertEqual(buildableReference.blueprintName, "App")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")
        XCTAssertEqual(
            result.storeKitConfigurationFileReference,
            .init(identifier: "../nested/configuration/configuration.storekit")
        )
        XCTAssertEqual(result.locationScenarioReference?.referenceType, "1")
        XCTAssertEqual(result.locationScenarioReference?.identifier, "New York, NY, USA")
        XCTAssertEqual(result.language, "pl")
    }

    func test_schemeLaunchAction_argumentsOrder() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let launchArguments = [
            LaunchArgument(name: "arg4", isEnabled: true),
            LaunchArgument(name: "arg2", isEnabled: false),
            LaunchArgument(name: "arg1", isEnabled: false),
            LaunchArgument(name: "arg3", isEnabled: false),
        ]

        let runAction = RunAction.test(
            configurationName: "Release",
            executable: TargetReference(projectPath: projectPath, name: "App"),
            arguments: Arguments(launchArguments: launchArguments)
        )
        let scheme = Scheme.test(runAction: runAction)

        let app = Target.test(name: "App", product: .app)

        let project = Project.test(path: projectPath, targets: [app])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")

        XCTAssertEqual(result.commandlineArguments, XCScheme.CommandLineArguments(arguments: [
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg4", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg2", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg1", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg3", enabled: false),
        ]))
    }

    func test_schemeLaunchAction_when_notRunnableTarget() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let launchAction = RunAction.test(
            configurationName: "Debug",
            filePath: "/usr/bin/foo",
            diagnosticsOptions: [.mainThreadChecker]
        )

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, runAction: launchAction)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertNil(result.runnable?.buildableReference)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.pathRunnable?.filePath, "/usr/bin/foo")
        XCTAssertFalse(result.disableMainThreadChecker)
        XCTAssertEqual(result.language, nil)
    }

    func test_schemeLaunchAction_with_path() throws {
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "Library"))],
            diagnosticsOptions: [.mainThreadChecker]
        )

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
        XCTAssertNil(result.runnable?.buildableReference)

        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.macroExpansion?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(result.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(result.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(result.macroExpansion?.buildableIdentifier, "primary")
        XCTAssertFalse(result.disableMainThreadChecker)
    }

    func test_schemeLaunchAction_with_executionAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "App")

        let preAction = ExecutionAction(
            title: "Pre Action",
            scriptText: "echo Pre Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )
        let postAction = ExecutionAction(
            title: "Post Action",
            scriptText: "echo Post Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )

        let launchAction = RunAction.test(
            preActions: [preAction],
            postActions: [postAction],
            executable: TargetReference(projectPath: projectPath, name: "App")
        )

        let scheme = Scheme.test(
            runAction: launchAction
        )
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")

        // Then
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")
        XCTAssertEqual(got?.preActions.first?.shellToInvoke, "/bin/sh")
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")
        XCTAssertEqual(got?.postActions.first?.shellToInvoke, "/bin/sh")
    }

    func test_schemeLaunchAction_with_disabled_attachDebugger() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let runAction = RunAction.test(
            configurationName: "Release",
            attachDebugger: false,
            executable: TargetReference(projectPath: projectPath, name: "App")
        )
        let scheme = Scheme.test(buildAction: buildAction, runAction: runAction)
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [app]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.IDEFoundation.Launcher.PosixSpawn")
    }

    func test_schemeLaunchAction_without_explicit_runAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let scheme = Scheme.test(buildAction: buildAction, runAction: nil)
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [app]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "Xcode.DebuggerFoundation.Debugger.LLDB")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.DebuggerFoundation.Launcher.LLDB")
    }

    func test_schemeLaunchAction_for_app_extension() throws {
        // Given
        let path = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let app = Target.test(name: "App", product: .app)
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let buildAction = BuildAction.test(targets: [
            TargetReference(projectPath: path, name: appExtension.name),
            TargetReference(projectPath: path, name: app.name),
        ])
        let runAction = RunAction.test(executable: TargetReference(projectPath: path, name: app.name))
        let extensionScheme = Scheme.test(buildAction: buildAction, runAction: runAction)
        let project = Project.test(
            path: path,
            targets: [app, appExtension],
            schemes: [
                extensionScheme,
            ]
        )

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    appExtension.name: appExtension,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: appExtension.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: extensionScheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "")
        XCTAssertEqual(result.selectedLauncherIdentifier, "Xcode.IDEFoundation.Launcher.PosixSpawn")
        XCTAssertEqual(result.askForAppToLaunch, true)
        XCTAssertEqual(result.launchAutomaticallySubstyle, "2")
    }

    func test_schemeLaunchAction_for_app_extension_with_disabled_attachDebugger() throws {
        // Given
        let path = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let app = Target.test(name: "App", product: .app)
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let buildAction = BuildAction.test(targets: [
            TargetReference(projectPath: path, name: appExtension.name),
            TargetReference(projectPath: path, name: app.name),
        ])
        let runAction = RunAction.test(
            attachDebugger: false,
            executable: TargetReference(projectPath: path, name: app.name)
        )
        let extensionScheme = Scheme.test(buildAction: buildAction, runAction: runAction)
        let project = Project.test(
            path: path,
            targets: [app, appExtension],
            schemes: [
                extensionScheme,
            ]
        )

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    appExtension.name: appExtension,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: appExtension.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: extensionScheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.selectedDebuggerIdentifier, "")
    }

    // MARK: - Profile Action Tests

    func test_schemeProfileAction_when_runnableTarget() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)

        let scheme = makeProfileActionScheme()
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        let buildable = try XCTUnwrap(result.buildableProductRunnable?.buildableReference)

        XCTAssertNil(result.macroExpansion)
        XCTAssertEqual(result.buildableProductRunnable?.runnableDebuggingMode, "0")
        XCTAssertEqual(buildable.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildable.buildableName, target.productNameWithExtension)
        XCTAssertEqual(buildable.blueprintName, target.name)
        XCTAssertEqual(buildable.buildableIdentifier, "primary")

        XCTAssertEqual(result.buildConfiguration, "Beta Release")
        XCTAssertEqual(result.preActions, [])
        XCTAssertEqual(result.postActions, [])
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertEqual(result.savedToolIdentifier, "")
        XCTAssertEqual(result.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(result.useCustomWorkingDirectory, false)
        XCTAssertEqual(result.debugDocumentVersioning, true)
        XCTAssertNil(result.commandlineArguments)
        XCTAssertNil(result.environmentVariables)
        XCTAssertEqual(result.enableTestabilityWhenProfilingTests, true)
    }

    func test_schemeProfileAction_when_notRunnableTarget() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let testAction = TestAction
            .test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "Library"))])
        let profileAction = ProfileAction.test(configurationName: "Beta Release", executable: nil)
        let scheme = Scheme.test(
            name: "Library",
            buildAction: buildAction,
            testAction: testAction,
            runAction: nil,
            profileAction: profileAction
        )

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        let buildable = result.buildableProductRunnable?.buildableReference

        XCTAssertNil(buildable)
        XCTAssertEqual(result.buildConfiguration, "Beta Release")
        XCTAssertEqual(result.preActions, [])
        XCTAssertEqual(result.postActions, [])
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertEqual(result.savedToolIdentifier, "")
        XCTAssertEqual(result.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(result.useCustomWorkingDirectory, false)
        XCTAssertEqual(result.debugDocumentVersioning, true)
        XCTAssertNil(result.commandlineArguments)
        XCTAssertNil(result.environmentVariables)
        XCTAssertEqual(result.enableTestabilityWhenProfilingTests, true)

        XCTAssertEqual(result.macroExpansion?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(result.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(result.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(result.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_schemeProfileAction_when_contains_launch_arguments() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)

        let scheme = makeProfileActionScheme(Arguments(launchArguments: [LaunchArgument(name: "something", isEnabled: true)]))
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        let buildable = try XCTUnwrap(result.buildableProductRunnable?.buildableReference)

        XCTAssertNil(result.macroExpansion)
        XCTAssertEqual(result.buildableProductRunnable?.runnableDebuggingMode, "0")
        XCTAssertEqual(buildable.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildable.buildableName, target.productNameWithExtension)
        XCTAssertEqual(buildable.blueprintName, target.name)
        XCTAssertEqual(buildable.buildableIdentifier, "primary")

        XCTAssertEqual(result.buildConfiguration, "Beta Release")
        XCTAssertEqual(result.preActions, [])
        XCTAssertEqual(result.postActions, [])
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, false)
        XCTAssertEqual(result.savedToolIdentifier, "")
        XCTAssertEqual(result.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(result.useCustomWorkingDirectory, false)
        XCTAssertEqual(result.debugDocumentVersioning, true)
        XCTAssertEqual(
            result.commandlineArguments,
            XCScheme.CommandLineArguments(arguments: [.init(name: "something", enabled: true)])
        )
        XCTAssertEqual(result.environmentVariables, [])
        XCTAssertEqual(result.enableTestabilityWhenProfilingTests, true)
    }

    func test_defaultSchemeProfileAction_when_runActionIsSpecified() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let appTargetReference = TargetReference(projectPath: projectPath, name: target.name)

        let buildAction = BuildAction.test(targets: [appTargetReference])
        let runAction = RunAction.test(
            executable: appTargetReference,
            arguments: Arguments(
                environment: ["SOME": "ENV"],
                launchArguments: [.init(name: "something", isEnabled: true)]
            )
        )
        let scheme = Scheme(name: "Scheme", buildAction: buildAction, runAction: runAction, profileAction: nil)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        let buildable = try XCTUnwrap(result.buildableProductRunnable?.buildableReference)

        XCTAssertNil(result.macroExpansion)
        XCTAssertEqual(result.buildableProductRunnable?.runnableDebuggingMode, "0")
        XCTAssertEqual(buildable.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(buildable.buildableName, target.productNameWithExtension)
        XCTAssertEqual(buildable.blueprintName, target.name)
        XCTAssertEqual(buildable.buildableIdentifier, "primary")

        XCTAssertEqual(result.buildConfiguration, "Release")
        XCTAssertEqual(result.preActions, [])
        XCTAssertEqual(result.postActions, [])
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertEqual(result.savedToolIdentifier, "")
        XCTAssertEqual(result.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(result.useCustomWorkingDirectory, false)
        XCTAssertEqual(result.debugDocumentVersioning, true)
        XCTAssertNil(result.commandlineArguments)
        XCTAssertNil(result.environmentVariables)
    }

    func test_schemeProfileAction_with_executionAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let target = Target.test(name: "App")

        let preAction = ExecutionAction(
            title: "Pre Action",
            scriptText: "echo Pre Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )
        let postAction = ExecutionAction(
            title: "Post Action",
            scriptText: "echo Post Actions",
            target: TargetReference(projectPath: projectPath, name: "App"),
            shellPath: "/bin/sh"
        )
        let scheme = makeProfileActionScheme(
            preActions: [preAction],
            postActions: [postAction]
        )
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeProfileAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")
        XCTAssertEqual(got?.preActions.first?.shellToInvoke, "/bin/sh")
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")
        XCTAssertEqual(got?.postActions.first?.shellToInvoke, "/bin/sh")
    }

    // MARK: - Analyze Action Tests

    func test_schemeAnalyzeAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let analyzeAction = AnalyzeAction.test(configurationName: "Beta Release")
        let scheme = Scheme.test(buildAction: buildAction, analyzeAction: analyzeAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeAnalyzeAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Beta Release")
    }

    func test_defaultSchemeArchiveAction() {
        let got = subject.defaultSchemeArchiveAction(for: .test())
        XCTAssertEqual(got.buildConfiguration, "Release")
        XCTAssertEqual(got.revealArchiveInOrganizer, true)
    }

    func test_schemeArchiveAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let archiveAction = ArchiveAction.test(
            configurationName: "Beta Release",
            revealArchiveInOrganizer: true,
            customArchiveName: "App [Beta]"
        )
        let scheme = Scheme.test(buildAction: buildAction, archiveAction: archiveAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target.name: target,
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeArchiveAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: project.path,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Beta Release")
        XCTAssertEqual(result.customArchiveName, "App [Beta]")
        XCTAssertEqual(result.revealArchiveInOrganizer, true)
    }

    func test_schemeGenerationModes_customOnly() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let unitTests = Target.test(name: "AppTests", product: .unitTests)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let scheme = Scheme.test()
        let project = Project.test(targets: [app, framework, unitTests, uiTests], schemes: [scheme])

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    framework.name: framework,
                    unitTests.name: unitTests,
                    uiTests.name: uiTests,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: framework.name, path: project.path),
                ],
                .target(name: unitTests.name, path: project.path): [
                    .target(name: app.name, path: project.path),
                ],
                .target(name: uiTests.name, path: project.path): [
                    .target(name: app.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject(targets: project.targets),
            graphTraverser: graphTraverser
        )

        // Then
        let schemes = result.map(\.xcScheme.name)
        XCTAssertEqual(schemes, [scheme.name])
    }

    func test_generate_appExtensionScheme() throws {
        let path = try AbsolutePath(validating: "/test")
        let app = Target.test(name: "App", product: .app)
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let appScheme = Scheme.test(buildAction: BuildAction(targets: [
            TargetReference(projectPath: path, name: app.name),
        ]))
        let extensionScheme = Scheme.test(buildAction: BuildAction.test(targets: [
            TargetReference(projectPath: path, name: appExtension.name),
            TargetReference(projectPath: path, name: app.name),
        ]))
        let project = Project.test(
            path: path,
            targets: [app, appExtension],
            schemes: [
                appScheme,
                extensionScheme,
            ]
        )

        let graph = Graph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    app.name: app,
                    appExtension.name: appExtension,
                ],
            ],
            dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: appExtension.name, path: project.path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject(targets: project.targets),
            graphTraverser: graphTraverser
        )

        // Then
        let schemeForExtension = result.map(\.xcScheme.wasCreatedForAppExtension)
        XCTAssertEqual(schemeForExtension, [
            nil, // Xcode omits the setting rather than have it set to `false`
            true,
        ])
    }

    func test_schemeGenerationLastUpgradeCheck_workspace() throws {
        // Given
        let target = Target.test()
        let project = Project.test(
            targets: [target],
            schemes: [.test()],
            lastUpgradeCheck: nil
        )
        let workspace = Workspace.test(
            projects: [project.path],
            schemes: [.test()],
            generationOptions: .test(lastXcodeUpgradeCheck: .init(13, 0, 0))
        )

        let graph = Graph.test(
            path: project.path,
            workspace: workspace,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [:]
        )
        let graphTraverser = GraphTraverser(graph: graph)
        let generatedProject = generatedProject(targets: project.targets)

        // When
        let result = try subject.generateWorkspaceSchemes(
            workspace: workspace,
            generatedProjects: [generatedProject.path: generatedProject],
            graphTraverser: graphTraverser
        )

        XCTAssertEqual(
            result.first?.xcScheme.lastUpgradeVersion,
            "1300"
        )
    }

    func test_schemeGenerationLastUpgradeCheck_project() throws {
        // Given
        let target = Target.test()
        let project = Project.test(
            targets: [target],
            schemes: [.test()],
            lastUpgradeCheck: .init(13, 0, 0)
        )

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [target.name: target]],
            dependencies: [:]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject(targets: project.targets),
            graphTraverser: graphTraverser
        )

        XCTAssertEqual(
            result.first?.xcScheme.lastUpgradeVersion,
            "1300"
        )
    }

    // MARK: - Helpers

    private func createGeneratedProjects(projects: [Project]) -> [AbsolutePath: GeneratedProject] {
        Dictionary(uniqueKeysWithValues: projects.map {
            (
                $0.xcodeProjPath,
                generatedProject(
                    targets: $0.targets,
                    projectPath: $0.xcodeProjPath.pathString
                )
            )
        })
    }

    private func generatedProject(targets: [Target], projectPath: String = "/Project.xcodeproj") -> GeneratedProject {
        var pbxTargets: [String: PBXNativeTarget] = [:]
        targets.forEach { pbxTargets[$0.name] = PBXNativeTarget(name: $0.name) }
        let path = try! AbsolutePath(validating: projectPath)
        return GeneratedProject(pbxproj: .init(), path: path, targets: pbxTargets, name: path.basename)
    }

    private func makeProfileActionScheme(
        _ launchArguments: Arguments? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = []
    ) -> Scheme {
        let projectPath = try! AbsolutePath(validating: "/somepath/Project")
        let appTargetReference = TargetReference(projectPath: projectPath, name: "App")
        let buildAction = BuildAction.test(targets: [appTargetReference])
        let testAction = TestAction.test(targets: [TestableTarget(target: appTargetReference)])
        let runAction = RunAction.test(configurationName: "Release", executable: appTargetReference, arguments: nil)
        let profileAction = ProfileAction.test(
            configurationName: "Beta Release",
            preActions: preActions,
            postActions: postActions,
            executable: appTargetReference,
            arguments: launchArguments
        )
        return Scheme.test(
            name: "App",
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction,
            profileAction: profileAction
        )
    }
}
