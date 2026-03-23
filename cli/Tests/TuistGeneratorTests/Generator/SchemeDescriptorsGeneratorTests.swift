import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
import Testing

@testable import TuistGenerator
@testable import TuistTesting

struct SchemeDescriptorsGeneratorTests {
    let subject: SchemeDescriptorsGenerator
    init() {
        subject = SchemeDescriptorsGenerator()
    }

    // MARK: - Build Action Tests

    @Test
    func test_schemeBuildAction_whenSingleProject() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]))

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: targets
        )
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.buildActionEntries.count == 1)
        let entry = try #require(result.buildActionEntries.first)
        let buildableReference = entry.buildableReference
        #expect(entry.buildFor == [.analyzing, .archiving, .profiling, .running, .testing])

        #expect(buildableReference.referencedContainer == "container:Projects/Project/Project.xcodeproj")
        #expect(buildableReference.buildableName == "App.app")
        #expect(buildableReference.blueprintName == "App")
        #expect(buildableReference.buildableIdentifier == "primary")

        #expect(result.parallelizeBuild == true)
        #expect(result.buildImplicitDependencies == true)
    }

    @Test
    func test_schemeBuildAction_findImplicitDependenciesFalse() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let xcodeProjPath = projectPath.appending(component: "Project.xcodeproj")
        let scheme = Scheme.test(
            buildAction: BuildAction(
                targets: [TargetReference(projectPath: projectPath, name: "App")],
                findImplicitDependencies: false
            )
        )

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: targets
        )
        let graph = Graph.test(
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeBuildAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: try AbsolutePath(validating: "/somepath/Workspace"),
            generatedProjects: [
                xcodeProjPath: generatedProject(targets: targets, projectPath: "\(xcodeProjPath)"),
            ]
        )

        // Then
        let result = try #require(got)
        #expect(result.buildImplicitDependencies == false)
    }

    @Test
    func test_schemeBuildAction_whenSingleProjectAndXcodeProjPathDiffers() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let xcodeProjPath = try AbsolutePath(validating: "/differentpath/Workspace/project.xcodeproj")
        let scheme = Scheme.test(buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]))

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: xcodeProjPath,
            targets: targets
        )
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.buildActionEntries.count == 1)
        let entry = try #require(result.buildActionEntries.first)
        let buildableReference = entry.buildableReference
        #expect(entry.buildFor == [.analyzing, .archiving, .profiling, .running, .testing])

        #expect(buildableReference.referencedContainer == "container:project.xcodeproj")
        #expect(buildableReference.buildableName == "App.app")
        #expect(buildableReference.blueprintName == "App")
        #expect(buildableReference.buildableIdentifier == "primary")

        #expect(result.parallelizeBuild == true)
        #expect(result.buildImplicitDependencies == true)
    }

    @Test
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
            xcodeProjPath: xcodeProjAPath,
            targets: [frameworkA]
        )
        let projectB = Project.test(
            path: projectBPath,
            xcodeProjPath: xcodeProjBPath,
            targets: [frameworkB]
        )
        let graph = Graph.test(
            projects: [
                projectA.path: projectA,
                projectB.path: projectB,
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
        let result = try #require(got)
        #expect(result.buildActionEntries.count == 2)

        let firstEntry = try #require(result.buildActionEntries[0])
        let firstBuildableReference = firstEntry.buildableReference
        #expect(firstEntry.buildFor == [.analyzing, .archiving, .profiling, .running, .testing])

        let secondEntry = try #require(result.buildActionEntries[1])
        let secondBuildableReference = secondEntry.buildableReference
        #expect(secondEntry.buildFor == [.analyzing, .archiving, .profiling, .running, .testing])

        #expect(firstBuildableReference.referencedContainer == "container:Projects/ProjectA/project.xcodeproj")
        #expect(firstBuildableReference.buildableName == "FrameworkA.framework")
        #expect(firstBuildableReference.blueprintName == "FrameworkA")
        #expect(firstBuildableReference.buildableIdentifier == "primary")

        #expect(secondBuildableReference.referencedContainer == "container:Projects/ProjectB/project.xcodeproj")
        #expect(secondBuildableReference.buildableName == "FrameworkB.framework")
        #expect(secondBuildableReference.blueprintName == "FrameworkB")
        #expect(secondBuildableReference.buildableIdentifier == "primary")

        #expect(result.parallelizeBuild == true)
        #expect(result.buildImplicitDependencies == true)
    }

    @Test
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
            projects: [project.path: project]
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
        #expect(got?.preActions.first?.title == "Pre Action")
        #expect(got?.preActions.first?.scriptText == "echo Pre Actions")
        #expect(got?.preActions.first?.shellToInvoke == "/bin/sh")

        let preBuildableReference = got?.preActions.first?.environmentBuildable

        #expect(preBuildableReference?.referencedContainer == "container:Project.xcodeproj")
        #expect(preBuildableReference?.buildableName == "App.app")
        #expect(preBuildableReference?.blueprintName == "App")
        #expect(preBuildableReference?.buildableIdentifier == "primary")

        // Post Action
        #expect(got?.postActions.first?.title == "Post Action")
        #expect(got?.postActions.first?.scriptText == "echo Post Actions")
        #expect(got?.postActions.first?.shellToInvoke == "/bin/sh")

        let postBuildableReference = got?.postActions.first?.environmentBuildable

        #expect(postBuildableReference?.referencedContainer == "container:Project.xcodeproj")
        #expect(postBuildableReference?.buildableName == "App.app")
        #expect(postBuildableReference?.blueprintName == "App")
        #expect(postBuildableReference?.buildableIdentifier == "primary")
    }

    @Test
    func test_buildAction_parallelizedBuild() throws {
        // Given
        let schemeA = Scheme(
            name: "SchemeA",
            buildAction: BuildAction(
                targets: [],
                parallelizeBuild: true
            )
        )
        let schemeB = Scheme(
            name: "SchemeB",
            buildAction: BuildAction(
                targets: [],
                parallelizeBuild: false
            )
        )
        let project = Project.test(schemes: [schemeA, schemeB])
        let generatedProject = generatedProject(targets: Array(project.targets.values))
        let graph = Graph.test(projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let schemeDescriptors = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject,
            graphTraverser: graphTraverser
        )

        // Then
        let buildActions = schemeDescriptors.compactMap(\.xcScheme.buildAction)
        #expect(buildActions.map(\.parallelizeBuild) == [
            true,
            false,
        ])
    }

    @Test
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
        let generatedProject = generatedProject(targets: Array(project.targets.values))
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
        #expect(buildActions.map(\.runPostActionsOnFailure) == [
            true,
            nil,
        ])
    }

    @Test
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
            projects: [project.path: project]
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

        let preBuildableReference = try #require(got?.preActions.first?.environmentBuildable)

        #expect(preBuildableReference.referencedContainer == "container:Projects/Project/Project.xcodeproj")
        #expect(preBuildableReference.buildableName == "App.app")
        #expect(preBuildableReference.blueprintName == "App")
        #expect(preBuildableReference.buildableIdentifier == "primary")
    }

    // MARK: - Test Action Tests

    @Test
    func test_schemeTestAction_when_testsTarget() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [
                TestableTarget(
                    target: TargetReference(projectPath: project.path, name: "AppTests"),
                    simulatedLocation: .reference("Rio de Janeiro, Brazil")
                ),
            ],
            arguments: nil
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.macroExpansion == nil)
        let testable = try #require(result.testables.first)
        let buildableReference = testable.buildableReference

        #expect(testable.skipped == false)
        #expect(testable.locationScenarioReference?.referenceType == "1")
        #expect(testable.locationScenarioReference?.identifier == "Rio de Janeiro, Brazil")
        #expect(buildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(buildableReference.buildableName == "AppTests.xctest")
        #expect(buildableReference.blueprintName == "AppTests")
        #expect(buildableReference.buildableIdentifier == "primary")
    }

    @Test
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        let testable = try #require(result.testables.first)
        let buildableReference = testable.buildableReference

        #expect(result.macroExpansion?.buildableName == "App.app")
        #expect(result.macroExpansion?.blueprintName == "App")
        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")

        #expect(testable.skipped == false)

        #expect(buildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(buildableReference.buildableName == "AppTests.xctest")
        #expect(buildableReference.blueprintName == "AppTests")
        #expect(buildableReference.buildableIdentifier == "primary")
    }

    @Test
    func test_schemeLaunchAction_with_expandVariable() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)

        let runAction = RunAction.test(
            executable: TargetReference(projectPath: projectPath, name: "App"),
            filePath: projectPath,
            expandVariableFromTarget: TargetReference(projectPath: projectPath, name: "Framework")
        )
        let scheme = Scheme.test(name: "Scheme", runAction: runAction)
        let project = Project.test(targets: [app, framework], schemes: [scheme])

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: projectPath): [
                    .target(name: framework.name, path: projectPath),
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
        let result = try #require(got)

        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")

        #expect(result.macroExpansion?.buildableName == "Framework.framework")
        #expect(result.macroExpansion?.blueprintName == "Framework")
        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")
    }

    @Test
    func test_schemeLaunchAction_with_customWorkingDirectoryEnabled() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)

        let runAction = RunAction.test(
            executable: TargetReference(projectPath: projectPath, name: "App"),
            filePath: projectPath,
            customWorkingDirectory: projectPath,
            useCustomWorkingDirectory: true
        )
        let scheme = Scheme.test(name: "Scheme", runAction: runAction)
        let project = Project.test(targets: [app, framework], schemes: [scheme])

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: projectPath): [
                    .target(name: framework.name, path: projectPath),
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
        let result = try #require(got)
        #expect(result.customWorkingDirectory == projectPath.pathString)
        #expect(result.useCustomWorkingDirectory == true)
    }

    @Test
    func test_schemeLaunchAction_with_launchStyle() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)

        let runAction = RunAction.test(
            executable: TargetReference(projectPath: projectPath, name: "App"),
            filePath: projectPath,
            expandVariableFromTarget: TargetReference(projectPath: projectPath, name: "Framework"),
            launchStyle: .waitForExecutableToBeLaunched
        )
        let scheme = Scheme.test(name: "Scheme", runAction: runAction)
        let project = Project.test(targets: [app, framework], schemes: [scheme])

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: projectPath): [
                    .target(name: framework.name, path: projectPath),
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
        let result = try #require(got)

        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.launchStyle == .wait)

        #expect(result.macroExpansion?.buildableName == "Framework.framework")
        #expect(result.macroExpansion?.blueprintName == "Framework")
        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")
    }

    @Test
    func test_schemeLaunchAction_with_appClips() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)

        let runAction = RunAction.test(
            executable: TargetReference(projectPath: projectPath, name: "App"),
            filePath: projectPath,
            expandVariableFromTarget: TargetReference(projectPath: projectPath, name: "Framework"),
            launchStyle: .waitForExecutableToBeLaunched,
            appClipInvocationURL: URL(string: "https://app-clips.com/example")
        )
        let scheme = Scheme.test(name: "Scheme", runAction: runAction)
        let project = Project.test(targets: [app, framework], schemes: [scheme])

        let graph = Graph.test(
            projects: [project.path: project],
            dependencies: [
                .target(name: app.name, path: projectPath): [
                    .target(name: framework.name, path: projectPath),
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
        let result = try #require(got)

        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.launchStyle == .wait)
        #expect(result.appClipInvocationURLString == "https://app-clips.com/example")

        #expect(result.macroExpansion?.buildableName == "Framework.framework")
        #expect(result.macroExpansion?.blueprintName == "Framework")
        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")
    }

    @Test
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        let codeCoverageTargetsBuildableReference = try #require(result.codeCoverageTargets)
        #expect(result.onlyGenerateCoverageForSpecifiedTargets == true)
        #expect(codeCoverageTargetsBuildableReference.count == 1)
        #expect(codeCoverageTargetsBuildableReference.first?.buildableName == "App.app")
    }

    @Test
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.shouldUseLaunchSchemeArgsEnv == false)
        #expect(result.macroExpansion == nil)
        #expect(result.testables.count == 0)
    }

    @Test
    func test_schemeTestAction_when_usingTestPlans() throws {
        // Given
        let project = Project.test()
        let planPath = try AbsolutePath(validating: "folder/Plan.xctestplan", relativeTo: project.path)
        let planList = [TestPlan(path: planPath, testTargets: [], isDefault: true)]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.testPlans?.count == 1)
        #expect(result.testPlans?.first?.reference == "container:folder/Plan.xctestplan")
    }

    @Test
    func test_schemeTestAction_when_usingTestPlans_with_disabled_attachDebugger() throws {
        // Given
        let project = Project.test()
        let planPath = try AbsolutePath(validating: "folder/Plan.xctestplan", relativeTo: project.path)
        let planList = [TestPlan(path: planPath, testTargets: [], isDefault: true)]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "")
        #expect(result.selectedLauncherIdentifier == "Xcode.IDEFoundation.Launcher.PosixSpawn")
        #expect(result.testPlans?.count == 1)
        #expect(result.testPlans?.first?.reference == "container:folder/Plan.xctestplan")
    }

    @Test
    func test_schemeTestAction_with_testable_info() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testableTarget = TestableTarget(
            target: TargetReference(projectPath: project.path, name: "AppTests"),
            skipped: false,
            parallelization: .all,
            randomExecutionOrdering: true
        )
        let testAction = TestAction.test(targets: [testableTarget])
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: project.path, name: "App")])

        let scheme = Scheme.test(name: "AppTests", shared: true, buildAction: buildAction, testAction: testAction)
        let graph = Graph.test(
            projects: [project.path: project],
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

        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")

        // Then
        let testableTargetReference = result.testables[0]
        #expect(testableTargetReference.skipped == false)
        #expect(testableTargetReference.parallelization == .all)
        #expect(testableTargetReference.randomExecutionOrdering == true)
    }

    @Test
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "")
        #expect(result.selectedLauncherIdentifier == "Xcode.IDEFoundation.Launcher.PosixSpawn")
    }

    @Test
    func test_schemeTestAction_with_preferredScreenCaptureFormat() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppUITests", product: .uiTests)

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
            preferredScreenCaptureFormat: .screenshots
        )
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])

        let scheme = Scheme.test(name: "AppUITests", shared: true, buildAction: buildAction, testAction: testAction)

        let project = Project.test(path: projectPath, targets: [target, testTarget])
        let graph = Graph.test(
            projects: [project.path: project],
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
        let result = try #require(got)
        #expect(result.preferredScreenCaptureFormat == .screenshots)
    }

    @Test
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.buildConfiguration == "Debug")
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.macroExpansion == nil)
        let testable = try #require(result.testables.first)
        let buildableReference = testable.buildableReference

        #expect(testable.skipped == false)
        #expect(buildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(buildableReference.buildableName == "AppTests.xctest")
        #expect(buildableReference.blueprintName == "AppTests")
        #expect(buildableReference.buildableIdentifier == "primary")
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.language == "es")
        #expect(result.region == "ES")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")

        #expect(result.preActions.first?.title == "Pre Action")
        #expect(result.preActions.first?.scriptText == "echo Pre Actions")
        #expect(result.preActions.first?.shellToInvoke == "/bin/sh")

        let preBuildableReference = try #require(result.preActions.first?.environmentBuildable)

        #expect(preBuildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(preBuildableReference.buildableName == "AppTests.xctest")
        #expect(preBuildableReference.blueprintName == "AppTests")
        #expect(preBuildableReference.buildableIdentifier == "primary")

        // Post Action
        #expect(result.postActions.first?.title == "Post Action")
        #expect(result.postActions.first?.scriptText == "echo Post Actions")
        #expect(result.postActions.first?.shellToInvoke == "/bin/sh")

        let postBuildableReference = try #require(result.postActions.first?.environmentBuildable)

        #expect(postBuildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(postBuildableReference.buildableName == "AppTests.xctest")
        #expect(postBuildableReference.blueprintName == "AppTests")
        #expect(postBuildableReference.buildableIdentifier == "primary")
    }

    @Test
    func test_schemeTestAction_when_testsTarget_with_skippedTests() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
            arguments: nil,
            skippedTests: ["AppTests/test_twoPlusTwo_isFour"]
        )

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.test(
            projects: [project.path: project],
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Debug")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.macroExpansion == nil)
        let testable = try #require(result.testables.first)
        let buildableReference = testable.buildableReference

        #expect(testable.skipped == false)
        #expect(buildableReference.referencedContainer == "container:Project.xcodeproj")
        #expect(buildableReference.buildableName == "AppTests.xctest")
        #expect(buildableReference.blueprintName == "AppTests")
        #expect(buildableReference.buildableIdentifier == "primary")
        #expect(testable.skippedTests == [XCScheme.TestItem(identifier: "AppTests/test_twoPlusTwo_isFour")])
    }

    // MARK: - Launch Action Tests

    @Test
    func test_schemeLaunchAction() throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/somepath/Workspace")
        let projectPath = workspacePath.appending(try RelativePath(validating: "Projects/Project"))
        let environmentVariables = [
            "env1": EnvironmentVariable(value: "1", isEnabled: true),
            "env2": EnvironmentVariable(value: "2", isEnabled: true),
            "env3": EnvironmentVariable(value: "3", isEnabled: true),
            "env4": EnvironmentVariable(value: "4", isEnabled: true),
        ]
        let launchArguments = [
            LaunchArgument(name: "arg1", isEnabled: true),
            LaunchArgument(name: "arg2", isEnabled: true),
            LaunchArgument(name: "arg3", isEnabled: false),
            LaunchArgument(name: "arg4", isEnabled: true),
        ]

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let runAction = RunAction.test(
            configurationName: "Release",
            customLLDBInitFile: workspacePath.appending(try RelativePath(validating: "Projects/etc/path/to/lldbinit")),
            executable: TargetReference(projectPath: projectPath, name: "App"),
            arguments: Arguments(environmentVariables: environmentVariables, launchArguments: launchArguments),
            options: .init(
                language: "pl",
                storeKitConfigurationPath: projectPath.appending(
                    try RelativePath(validating: "nested/configuration/configuration.storekit")
                ),
                simulatedLocation: .reference("New York, NY, USA"),
                enableGPUFrameCaptureMode: .metal
            )
        )

        let scheme = Scheme.test(buildAction: buildAction, runAction: runAction)

        let app = Target.test(name: "App", product: .app, environmentVariables: environmentVariables)

        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [app]
        )
        let graph = Graph.test(
            path: workspacePath,
            workspace: .test(
                path: workspacePath,
                xcWorkspacePath: workspacePath.appending(component: "Workspace.xcworkspace")
            ),
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: workspacePath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )

        // Then
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.macroExpansion == nil)

        let buildableReference = try #require(result.runnable?.buildableReference)

        #expect(result.buildConfiguration == "Release")
        #expect(result.commandlineArguments == XCScheme.CommandLineArguments(arguments: [
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg1", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg2", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg3", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg4", enabled: true),
        ]))
        #expect(result.environmentVariables == [
            XCScheme.EnvironmentVariable(variable: "env1", value: "1", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env2", value: "2", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env3", value: "3", enabled: true),
            XCScheme.EnvironmentVariable(variable: "env4", value: "4", enabled: true),
        ])
        #expect(result.askForAppToLaunch == nil)
        #expect(result.launchAutomaticallySubstyle == nil)
        #expect(result.customLLDBInitFile == "$(SRCROOT)/../etc/path/to/lldbinit")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(buildableReference.referencedContainer == "container:Projects/Project/Project.xcodeproj")
        #expect(buildableReference.buildableName == "App.app")
        #expect(buildableReference.blueprintName == "App")
        #expect(buildableReference.buildableIdentifier == "primary")
        #expect(result.storeKitConfigurationFileReference == .init(identifier: "../Projects/Project/nested/configuration/configuration.storekit"))
        #expect(result.locationScenarioReference?.referenceType == "1")
        #expect(result.locationScenarioReference?.identifier == "New York, NY, USA")
        #expect(result.language == "pl")
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")

        #expect(result.commandlineArguments == XCScheme.CommandLineArguments(arguments: [
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg4", enabled: true),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg2", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg1", enabled: false),
            XCScheme.CommandLineArguments.CommandLineArgument(name: "arg3", enabled: false),
        ]))
    }

    @Test
    func test_schemeLaunchAction_when_notRunnableTarget() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let launchAction = RunAction.test(
            configurationName: "Debug",
            filePath: "/usr/bin/foo",
            diagnosticsOptions: SchemeDiagnosticsOptions(mainThreadCheckerEnabled: true)
        )

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, runAction: launchAction)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.runnable?.buildableReference == nil)
        #expect(result.buildConfiguration == "Debug")
        #expect(result.pathRunnable?.filePath == "/usr/bin/foo")
        #expect(!result.disableMainThreadChecker)
        #expect(result.language == nil)
    }

    @Test
    func test_schemeLaunchAction_with_path() throws {
        let projectPath = try AbsolutePath(validating: "/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let testAction = TestAction.test(
            targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "Library"))],
            diagnosticsOptions: SchemeDiagnosticsOptions(mainThreadCheckerEnabled: true)
        )

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.runnable?.buildableReference == nil)

        #expect(result.buildConfiguration == "Debug")
        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableName == "libLibrary.dylib")
        #expect(result.macroExpansion?.blueprintName == "Library")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")
        #expect(!result.disableMainThreadChecker)
    }

    @Test
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
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = try subject.schemeLaunchAction(
            scheme: scheme,
            graphTraverser: graphTraverser,
            rootPath: projectPath,
            generatedProjects: createGeneratedProjects(projects: [project])
        )
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")

        // Then
        #expect(got?.preActions.first?.title == "Pre Action")
        #expect(got?.preActions.first?.scriptText == "echo Pre Actions")
        #expect(got?.preActions.first?.shellToInvoke == "/bin/sh")
        #expect(got?.postActions.first?.title == "Post Action")
        #expect(got?.postActions.first?.scriptText == "echo Post Actions")
        #expect(got?.postActions.first?.shellToInvoke == "/bin/sh")
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "")
        #expect(result.selectedLauncherIdentifier == "Xcode.IDEFoundation.Launcher.PosixSpawn")
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
    }

    @Test
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "")
        #expect(result.selectedLauncherIdentifier == "Xcode.IDEFoundation.Launcher.PosixSpawn")
        #expect(result.askForAppToLaunch == true)
        #expect(result.launchAutomaticallySubstyle == "2")
    }

    @Test
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
        let result = try #require(got)
        #expect(result.selectedDebuggerIdentifier == "")
    }

    @Test
    func test_schemeLaunchAction_askForAppToLaunch() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Workspace/Projects/Project")
        let target = Target.test(name: "App", product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let runAction = RunAction.test(
            executable: TargetReference(projectPath: projectPath, name: "App"),
            askForAppToLaunch: true
        )
        let scheme = Scheme.test(buildAction: buildAction, runAction: runAction)
        let project = Project.test(
            path: projectPath,
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.askForAppToLaunch == true)
        #expect(result.launchAutomaticallySubstyle == "2")
        #expect(result.selectedLauncherIdentifier == "Xcode.DebuggerFoundation.Launcher.LLDB")
        #expect(result.selectedDebuggerIdentifier == "Xcode.DebuggerFoundation.Debugger.LLDB")
    }

    // MARK: - Profile Action Tests

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        let buildable = try #require(result.buildableProductRunnable?.buildableReference)

        #expect(result.macroExpansion == nil)
        #expect(result.buildableProductRunnable?.runnableDebuggingMode == "0")
        #expect(buildable.referencedContainer == "container:Project.xcodeproj")
        #expect(buildable.buildableName == target.productNameWithExtension)
        #expect(buildable.blueprintName == target.name)
        #expect(buildable.buildableIdentifier == "primary")

        #expect(result.buildConfiguration == "Beta Release")
        #expect(result.preActions == [])
        #expect(result.postActions == [])
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.savedToolIdentifier == "")
        #expect(result.ignoresPersistentStateOnLaunch == false)
        #expect(result.useCustomWorkingDirectory == false)
        #expect(result.debugDocumentVersioning == true)
        #expect(result.commandlineArguments == nil)
        #expect(result.environmentVariables == nil)
        #expect(result.enableTestabilityWhenProfilingTests == true)
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        let buildable = result.buildableProductRunnable?.buildableReference

        #expect(buildable == nil)
        #expect(result.buildConfiguration == "Beta Release")
        #expect(result.preActions == [])
        #expect(result.postActions == [])
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.savedToolIdentifier == "")
        #expect(result.ignoresPersistentStateOnLaunch == false)
        #expect(result.useCustomWorkingDirectory == false)
        #expect(result.debugDocumentVersioning == true)
        #expect(result.commandlineArguments == nil)
        #expect(result.environmentVariables == nil)
        #expect(result.enableTestabilityWhenProfilingTests == true)

        #expect(result.macroExpansion?.referencedContainer == "container:Project.xcodeproj")
        #expect(result.macroExpansion?.buildableName == "libLibrary.dylib")
        #expect(result.macroExpansion?.blueprintName == "Library")
        #expect(result.macroExpansion?.buildableIdentifier == "primary")
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        let buildable = try #require(result.buildableProductRunnable?.buildableReference)

        #expect(result.macroExpansion == nil)
        #expect(result.buildableProductRunnable?.runnableDebuggingMode == "0")
        #expect(buildable.referencedContainer == "container:Project.xcodeproj")
        #expect(buildable.buildableName == target.productNameWithExtension)
        #expect(buildable.blueprintName == target.name)
        #expect(buildable.buildableIdentifier == "primary")

        #expect(result.buildConfiguration == "Beta Release")
        #expect(result.preActions == [])
        #expect(result.postActions == [])
        #expect(result.shouldUseLaunchSchemeArgsEnv == false)
        #expect(result.savedToolIdentifier == "")
        #expect(result.ignoresPersistentStateOnLaunch == false)
        #expect(result.useCustomWorkingDirectory == false)
        #expect(result.debugDocumentVersioning == true)
        #expect(result.commandlineArguments == XCScheme.CommandLineArguments(arguments: [.init(name: "something", enabled: true)]))
        #expect(result.environmentVariables == [])
        #expect(result.enableTestabilityWhenProfilingTests == true)
    }

    @Test
    func test_defaultSchemeProfileAction_when_runActionIsSpecified() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let appTargetReference = TargetReference(projectPath: projectPath, name: target.name)

        let buildAction = BuildAction.test(targets: [appTargetReference])
        let runAction = RunAction.test(
            executable: appTargetReference,
            arguments: Arguments(
                environmentVariables: ["SOME": EnvironmentVariable(value: "ENV", isEnabled: true)],
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
            projects: [project.path: project]
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
        let result = try #require(got)
        let buildable = try #require(result.buildableProductRunnable?.buildableReference)

        #expect(result.macroExpansion == nil)
        #expect(result.buildableProductRunnable?.runnableDebuggingMode == "0")
        #expect(buildable.referencedContainer == "container:Project.xcodeproj")
        #expect(buildable.buildableName == target.productNameWithExtension)
        #expect(buildable.blueprintName == target.name)
        #expect(buildable.buildableIdentifier == "primary")

        #expect(result.buildConfiguration == "Release")
        #expect(result.preActions == [])
        #expect(result.postActions == [])
        #expect(result.shouldUseLaunchSchemeArgsEnv == true)
        #expect(result.savedToolIdentifier == "")
        #expect(result.ignoresPersistentStateOnLaunch == false)
        #expect(result.useCustomWorkingDirectory == false)
        #expect(result.debugDocumentVersioning == true)
        #expect(result.commandlineArguments == nil)
        #expect(result.environmentVariables == nil)
    }

    @Test
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
            projects: [project.path: project]
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
        #expect(got?.preActions.first?.title == "Pre Action")
        #expect(got?.preActions.first?.scriptText == "echo Pre Actions")
        #expect(got?.preActions.first?.shellToInvoke == "/bin/sh")
        #expect(got?.postActions.first?.title == "Post Action")
        #expect(got?.postActions.first?.scriptText == "echo Post Actions")
        #expect(got?.postActions.first?.shellToInvoke == "/bin/sh")
    }

    @Test
    func test_schemeProfileAction_askForAppToLaunch() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let appTargetReference = TargetReference(projectPath: projectPath, name: "App")
        let buildAction = BuildAction.test(targets: [appTargetReference])
        let profileAction = ProfileAction.test(
            executable: appTargetReference,
            askForAppToLaunch: true
        )
        let scheme = Scheme.test(
            name: "App",
            buildAction: buildAction,
            profileAction: profileAction
        )
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.askForAppToLaunch == true)
        #expect(result.launchAutomaticallySubstyle == "2")
    }

    // MARK: - Analyze Action Tests

    @Test
    func test_schemeAnalyzeAction() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let analyzeAction = AnalyzeAction.test(configurationName: "Beta Release")
        let scheme = Scheme.test(buildAction: buildAction, analyzeAction: analyzeAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Beta Release")
    }

    @Test
    func test_defaultSchemeArchiveAction() {
        let got = subject.defaultSchemeArchiveAction(for: .test())
        #expect(got.buildConfiguration == "Release")
        #expect(got.revealArchiveInOrganizer == true)
    }

    @Test
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
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Beta Release")
        #expect(result.customArchiveName == "App [Beta]")
        #expect(result.revealArchiveInOrganizer == true)
    }

    @Test
    func test_schemeArchiveAction_whenNoBuildActionSpecified() throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let archiveAction = ArchiveAction.test(
            configurationName: "Beta Release",
            revealArchiveInOrganizer: true,
            customArchiveName: "App [Beta]"
        )
        let scheme = Scheme.test(
            buildAction: nil,
            archiveAction: archiveAction
        )

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.test(
            projects: [project.path: project]
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
        let result = try #require(got)
        #expect(result.buildConfiguration == "Beta Release")
        #expect(result.customArchiveName == "App [Beta]")
        #expect(result.revealArchiveInOrganizer == true)
    }

    @Test
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
            generatedProject: generatedProject(targets: Array(project.targets.values)),
            graphTraverser: graphTraverser
        )

        // Then
        let schemes = result.map(\.xcScheme.name)
        #expect(schemes == [scheme.name])
    }

    @Test
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
            generatedProject: generatedProject(targets: Array(project.targets.values)),
            graphTraverser: graphTraverser
        )

        // Then
        let schemeForExtension = result.map(\.xcScheme.wasCreatedForAppExtension)
        #expect(schemeForExtension == [
            nil, // Xcode omits the setting rather than have it set to `false`
            true,
        ])
    }

    @Test
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
            dependencies: [:]
        )
        let graphTraverser = GraphTraverser(graph: graph)
        let generatedProject = generatedProject(targets: Array(project.targets.values))

        // When
        let result = try subject.generateWorkspaceSchemes(
            workspace: workspace,
            generatedProjects: [generatedProject.path: generatedProject],
            graphTraverser: graphTraverser
        )

        #expect(result.first?.xcScheme.lastUpgradeVersion == "1300")
    }

    @Test
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
            dependencies: [:]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try subject.generateProjectSchemes(
            project: project,
            generatedProject: generatedProject(targets: Array(project.targets.values)),
            graphTraverser: graphTraverser
        )

        #expect(result.first?.xcScheme.lastUpgradeVersion == "1300")
    }

    // MARK: - Helpers

    private func createGeneratedProjects(projects: [Project]) -> [AbsolutePath: GeneratedProject] {
        Dictionary(uniqueKeysWithValues: projects.map {
            (
                $0.xcodeProjPath,
                generatedProject(
                    targets: Array($0.targets.values),
                    projectPath: $0.xcodeProjPath.pathString
                )
            )
        })
    }

    private func generatedProject(targets: [Target], projectPath: String = "/Project.xcodeproj") -> GeneratedProject {
        var pbxTargets: [String: PBXTarget] = [:]
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
