import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupportTesting

final class SchemesGeneratorTests: XCTestCase {
    var subject: SchemesGenerator!

    override func setUp() {
        super.setUp()
        subject = SchemesGenerator()
    }

    // MARK: - Scheme Generation

    func test_defaultGeneratedScheme_RegularTarget() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget1 = Target.test(name: "AppTests1", product: .unitTests)
        let testTarget2 = Target.test(name: "AppTests2", product: .unitTests)
        let testTarget3 = Target.test(name: "AppTests3", product: .unitTests)
        let testTargets = [testTarget1, testTarget2, testTarget3]
        let project = Project.test(targets: [target] + testTargets)

        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget1, dependencies: [target]),
                                                (project: project, target: testTarget2, dependencies: [target]),
                                                (project: project, target: testTarget3, dependencies: [target])])

        // When
        let got = subject.createDefaultScheme(target: target, project: project, buildConfiguration: "Debug", graph: graph)

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.name, target.name)
        XCTAssertTrue(result.shared)

        let buildAction = try XCTUnwrap(result.buildAction)
        let targetReference = TargetReference(projectPath: project.path, name: target.name)
        XCTAssertEqual(buildAction.targets, [targetReference])

        let testAction = try XCTUnwrap(result.testAction)
        let testableTargests = testTargets
            .map { TargetReference(projectPath: project.path, name: $0.name) }
            .map { TestableTarget(target: $0) }
        XCTAssertEqual(testAction.targets, testableTargests)
    }

    func test_defaultGeneratedScheme_TestTarget() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget, dependencies: [target])])

        // When
        let got = subject.createDefaultScheme(target: testTarget, project: project, buildConfiguration: "Debug", graph: graph)

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.name, testTarget.name)
        XCTAssertTrue(result.shared)

        let buildAction = try XCTUnwrap(result.buildAction)
        let targetReference = TargetReference(projectPath: project.path, name: testTarget.name)
        XCTAssertEqual(buildAction.targets, [targetReference])

        let testAction = try XCTUnwrap(result.testAction)
        let testTargetReference = TargetReference(projectPath: project.path, name: testTarget.name)
        let testableTarget = TestableTarget(target: testTargetReference)
        XCTAssertEqual(testAction.targets, [testableTarget])
    }

    // MARK: - Build Action Tests

    func test_schemeBuildAction_whenSingleProject() throws {
        // Given
        let projectPath = AbsolutePath("/somepath/Workspace/Projects/Project")
        let scheme = Scheme.test(buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]))

        let app = Target.test(name: "App", product: .app)
        let targets = [app]

        let project = Project.test(path: projectPath)
        let graph = Graph.create(dependencies: [(project: project, target: app, dependencies: [])])

        // Then
        let got = try subject.schemeBuildAction(scheme: scheme,
                                                graph: graph,
                                                rootPath: AbsolutePath("/somepath/Workspace"),
                                                generatedProjects: [projectPath:
                                                    generatedProject(targets: targets, projectPath: "\(projectPath)/project.xcodeproj")])

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildActionEntries.count, 1)
        let entry = try XCTUnwrap(result.buildActionEntries.first)
        let buildableReference = entry.buildableReference
        XCTAssertEqual(entry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(buildableReference.referencedContainer, "container:Projects/Project/project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "App.app")
        XCTAssertEqual(buildableReference.blueprintName, "App")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(result.parallelizeBuild, true)
        XCTAssertEqual(result.buildImplicitDependencies, true)
    }

    func test_schemeBuildAction_whenMultipleProject() throws {
        // Given
        let projectAPath = AbsolutePath("/somepath/Workspace/Projects/ProjectA")
        let projectBPath = AbsolutePath("/somepath/Workspace/Projects/ProjectB")

        let buildAction = BuildAction(targets: [
            TargetReference(projectPath: projectAPath, name: "FrameworkA"),
            TargetReference(projectPath: projectBPath, name: "FrameworkB"),
        ])
        let scheme = Scheme.test(buildAction: buildAction)

        let frameworkA = Target.test(name: "FrameworkA", product: .staticFramework)
        let frameworkB = Target.test(name: "FrameworkB", product: .staticFramework)
        let targets = [frameworkA, frameworkB]

        let projectA = Project.test(path: projectAPath)
        let projectB = Project.test(path: projectBPath)
        let graph = Graph.create(dependencies: [
            (project: projectA, target: frameworkA, dependencies: []),
            (project: projectB, target: frameworkB, dependencies: []),
        ])

        // Then
        let got = try subject.schemeBuildAction(scheme: scheme,
                                                graph: graph,
                                                rootPath: AbsolutePath("/somepath/Workspace"),
                                                generatedProjects: [
                                                    projectAPath: generatedProject(targets: targets, projectPath: "\(projectAPath)/project.xcodeproj"),
                                                    projectBPath: generatedProject(targets: targets, projectPath: "\(projectBPath)/project.xcodeproj"),
                                                ])

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
        let projectPath = AbsolutePath("/somepath/Project")
        let target = Target.test(name: "App", product: .app)

        let preAction = ExecutionAction(title: "Pre Action", scriptText: "echo Pre Actions", target: TargetReference(projectPath: projectPath, name: "App"))
        let postAction = ExecutionAction(title: "Post Action", scriptText: "echo Post Actions", target: TargetReference(projectPath: projectPath, name: "App"))
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")], preActions: [preAction], postActions: [postAction])

        let scheme = Scheme.test(name: "App", shared: true, buildAction: buildAction)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [
            (project: project, target: target, dependencies: []),
        ])

        // When
        let got = try subject.schemeBuildAction(scheme: scheme,
                                                graph: graph,
                                                rootPath: projectPath,
                                                generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        // Pre Action
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")

        let preBuildableReference = got?.preActions.first?.environmentBuildable

        XCTAssertEqual(preBuildableReference?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(preBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(preBuildableReference?.blueprintName, "App")
        XCTAssertEqual(preBuildableReference?.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")

        let postBuildableReference = got?.postActions.first?.environmentBuildable

        XCTAssertEqual(postBuildableReference?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(postBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(postBuildableReference?.blueprintName, "App")
        XCTAssertEqual(postBuildableReference?.buildableIdentifier, "primary")
    }

    // MARK: - Test Action Tests

    func test_schemeTestAction_when_testsTarget() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
                                         arguments: nil)

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget, dependencies: [target])])

        // When
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: project.path, generatedProjects: generatedProjects)

        // Then
        let result = try XCTUnwrap(got)
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

    func test_schemeTestAction_with_codeCoverageTargets() throws {
        // Given
        let projectPath = AbsolutePath("/somepath/Project")

        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
                                         coverage: true,
                                         codeCoverageTargets: [TargetReference(projectPath: projectPath, name: "App")])
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])

        let scheme = Scheme.test(name: "AppTests", shared: true, buildAction: buildAction, testAction: testAction)

        let project = Project.test(path: projectPath, targets: [target, testTarget])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget, dependencies: [target])])

        // When
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: AbsolutePath("/somepath/Workspace"), generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let result = try XCTUnwrap(got)
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
        let graph = Graph.create(dependencies: [])

        // Then
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: project.path, generatedProjects: [project.path: generatedProject])

        // When
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.shouldUseLaunchSchemeArgsEnv, false)
        XCTAssertNil(result.macroExpansion)
        XCTAssertEqual(result.testables.count, 0)
    }

    func test_schemeTestAction_with_testable_info() throws {
        // Given
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testableTarget = TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"),
                                            skipped: false,
                                            parallelizable: true,
                                            randomExecutionOrdering: true)
        let testAction = TestAction.test(targets: [testableTarget])
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: project.path, name: "App")])

        let scheme = Scheme.test(name: "AppTests", shared: true, buildAction: buildAction, testAction: testAction)
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget, dependencies: [testTarget])])

        // When
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: project.path, generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let testableTargetReference = got!.testables[0]
        XCTAssertEqual(testableTargetReference.skipped, false)
        XCTAssertEqual(testableTargetReference.parallelizable, true)
        XCTAssertEqual(testableTargetReference.randomExecutionOrdering, true)
    }

    func test_schemeBuildAction() throws {
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(targets: [target, testTarget])

        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: project.path, name: "AppTests"))],
                                         arguments: nil)

        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let generatedProjects = createGeneratedProjects(projects: [project])

        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: []),
                                                (project: project, target: testTarget, dependencies: [target])])

        // When
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: project.path, generatedProjects: generatedProjects)

        // Then
        let result = try XCTUnwrap(got)
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
        let projectPath = AbsolutePath("/somepath/Project")
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let preAction = ExecutionAction(title: "Pre Action", scriptText: "echo Pre Actions", target: TargetReference(projectPath: projectPath, name: "AppTests"))
        let postAction = ExecutionAction(title: "Post Action", scriptText: "echo Post Actions", target: TargetReference(projectPath: projectPath, name: "AppTests"))
        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))], preActions: [preAction], postActions: [postAction])

        let scheme = Scheme.test(name: "AppTests", shared: true, testAction: testAction)
        let project = Project.test(path: projectPath, targets: [testTarget])

        let generatedProjects = createGeneratedProjects(projects: [project])
        let graph = Graph.create(dependencies: [(project: project, target: testTarget, dependencies: [])])

        // When
        let got = try subject.schemeTestAction(scheme: scheme, graph: graph, rootPath: project.path, generatedProjects: generatedProjects)

        // Then
        // Pre Action
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.preActions.first?.title, "Pre Action")
        XCTAssertEqual(result.preActions.first?.scriptText, "echo Pre Actions")

        let preBuildableReference = try XCTUnwrap(result.preActions.first?.environmentBuildable)

        XCTAssertEqual(preBuildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(preBuildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(preBuildableReference.blueprintName, "AppTests")
        XCTAssertEqual(preBuildableReference.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(result.postActions.first?.title, "Post Action")
        XCTAssertEqual(result.postActions.first?.scriptText, "echo Post Actions")

        let postBuildableReference = try XCTUnwrap(result.postActions.first?.environmentBuildable)

        XCTAssertEqual(postBuildableReference.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(postBuildableReference.buildableName, "AppTests.xctest")
        XCTAssertEqual(postBuildableReference.blueprintName, "AppTests")
        XCTAssertEqual(postBuildableReference.buildableIdentifier, "primary")
    }

    // MARK: - Launch Action Tests

    func test_schemeLaunchAction() throws {
        // Given
        let projectPath = AbsolutePath("/somepath/Workspace/Projects/Project")
        let environment = ["env1": "1", "env2": "2", "env3": "3", "env4": "4"]
        let launch = ["arg1": true, "arg2": true, "arg3": false, "arg4": true]

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let runAction = RunAction.test(configurationName: "Release",
                                       executable: TargetReference(projectPath: projectPath, name: "App"),
                                       arguments: Arguments(environment: environment, launch: launch))
        let scheme = Scheme.test(buildAction: buildAction, runAction: runAction)

        let app = Target.test(name: "App", product: .app, environment: environment)

        let project = Project.test(path: projectPath, targets: [app])
        let graph = Graph.create(dependencies: [(project: project, target: app, dependencies: [])])

        // When
        let got = try subject.schemeLaunchAction(scheme: scheme,
                                                 graph: graph,
                                                 rootPath: AbsolutePath("/somepath/Workspace"),
                                                 generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let result = try XCTUnwrap(got)

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
        XCTAssertEqual(buildableReference.referencedContainer, "container:Projects/Project/Project.xcodeproj")
        XCTAssertEqual(buildableReference.buildableName, "App.app")
        XCTAssertEqual(buildableReference.blueprintName, "App")
        XCTAssertEqual(buildableReference.buildableIdentifier, "primary")
    }

    func test_schemeLaunchAction_when_notRunnableTarget() throws {
        // Given
        let projectPath = AbsolutePath("/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let launchAction = RunAction.test(configurationName: "Debug", filePath: "/usr/bin/foo")

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, runAction: launchAction)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeLaunchAction(scheme: scheme,
                                                 graph: graph,
                                                 rootPath: projectPath,
                                                 generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertNil(result.runnable?.buildableReference)
        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.pathRunnable?.filePath, "/usr/bin/foo")
    }

    func test_schemeLaunchAction_with_path() throws {
        let projectPath = AbsolutePath("/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "Library"))])

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeLaunchAction(scheme: scheme,
                                                 graph: graph,
                                                 rootPath: projectPath,
                                                 generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertNil(result.runnable?.buildableReference)

        XCTAssertEqual(result.buildConfiguration, "Debug")
        XCTAssertEqual(result.macroExpansion?.referencedContainer, "container:Project.xcodeproj")
        XCTAssertEqual(result.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(result.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(result.macroExpansion?.buildableIdentifier, "primary")
    }

    // MARK: - Profile Action Tests

    func test_schemeProfileAction_when_runnableTarget() throws {
        // Given
        let projectPath = AbsolutePath("/somepath/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)

        let appTargetReference = TargetReference(projectPath: projectPath, name: "App")
        let buildAction = BuildAction.test(targets: [appTargetReference])
        let testAction = TestAction.test(targets: [TestableTarget(target: appTargetReference)])
        let runAction = RunAction.test(configurationName: "Release", executable: appTargetReference, arguments: nil)
        let profileAction = ProfileAction.test(configurationName: "Beta Release", executable: appTargetReference, arguments: nil)

        let scheme = Scheme.test(name: "App", buildAction: buildAction, testAction: testAction, runAction: runAction, profileAction: profileAction)
        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeProfileAction(scheme: scheme,
                                                  graph: graph,
                                                  rootPath: projectPath,
                                                  generatedProjects: createGeneratedProjects(projects: [project]))

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
        let projectPath = AbsolutePath("/somepath/Project")

        let target = Target.test(name: "Library", platform: .iOS, product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "Library")])
        let testAction = TestAction.test(targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "Library"))])
        let profileAction = ProfileAction.test(configurationName: "Beta Release", executable: nil)
        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil, profileAction: profileAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeProfileAction(scheme: scheme,
                                                  graph: graph,
                                                  rootPath: projectPath,
                                                  generatedProjects: createGeneratedProjects(projects: [project]))

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

    // MARK: - Analyze Action Tests

    func test_schemeAnalyzeAction() throws {
        // Given
        let projectPath = AbsolutePath("/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let analyzeAction = AnalyzeAction.test(configurationName: "Beta Release")
        let scheme = Scheme.test(buildAction: buildAction, analyzeAction: analyzeAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeAnalyzeAction(scheme: scheme,
                                                  graph: graph,
                                                  rootPath: project.path,
                                                  generatedProjects: createGeneratedProjects(projects: [project]))

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
        let projectPath = AbsolutePath("/Project")
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let buildAction = BuildAction.test(targets: [TargetReference(projectPath: projectPath, name: "App")])
        let archiveAction = ArchiveAction.test(configurationName: "Beta Release",
                                               revealArchiveInOrganizer: true,
                                               customArchiveName: "App [Beta]")
        let scheme = Scheme.test(buildAction: buildAction, archiveAction: archiveAction)

        let project = Project.test(path: projectPath, targets: [target])
        let graph = Graph.create(dependencies: [(project: project, target: target, dependencies: [])])

        // When
        let got = try subject.schemeArchiveAction(scheme: scheme,
                                                  graph: graph,
                                                  rootPath: project.path,
                                                  generatedProjects: createGeneratedProjects(projects: [project]))

        // Then
        let result = try XCTUnwrap(got)
        XCTAssertEqual(result.buildConfiguration, "Beta Release")
        XCTAssertEqual(result.customArchiveName, "App [Beta]")
        XCTAssertEqual(result.revealArchiveInOrganizer, true)
    }

    func test_schemeGenerationModes_default() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let unitTests = Target.test(name: "AppTests", product: .unitTests)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let project = Project.test(targets: [app, framework, unitTests, uiTests])

        let graph = Graph.create(
            project: project,
            dependencies: [
                (target: app, dependencies: [framework]),
                (target: framework, dependencies: []),
                (target: unitTests, dependencies: [app]),
                (target: uiTests, dependencies: [app]),
            ]
        )

        // When
        let result = try subject.generateProjectSchemes(project: project,
                                                        generatedProject: generatedProject(targets: project.targets),
                                                        graph: graph)

        // Then
        let schemes = result.map(\.xcScheme.name)
        XCTAssertEqual(schemes, [
            "App",
            "Framework",
            "AppTests",
            "AppUITests",
        ])
    }

    func test_schemeGenerationModes_customOnly() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let unitTests = Target.test(name: "AppTests", product: .unitTests)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let scheme = Scheme.test()
        let project = Project.test(targets: [app, framework, unitTests, uiTests], schemes: [scheme], autogenerateSchemes: false)

        let graph = Graph.create(
            project: project,
            dependencies: [
                (target: app, dependencies: [framework]),
                (target: framework, dependencies: []),
                (target: unitTests, dependencies: [app]),
                (target: uiTests, dependencies: [app]),
            ]
        )

        // When
        let result = try subject.generateProjectSchemes(project: project,
                                                        generatedProject: generatedProject(targets: project.targets),
                                                        graph: graph)

        // Then
        let schemes = result.map(\.xcScheme.name)
        XCTAssertEqual(schemes, [scheme.name])
    }

    private func createGeneratedProjects(projects: [Project]) -> [AbsolutePath: GeneratedProject] {
        Dictionary(uniqueKeysWithValues: projects.map {
            ($0.path, generatedProject(targets: $0.targets,
                                       projectPath: $0.path.appending(component: "\($0.name).xcodeproj").pathString))
        })
    }

    private func generatedProject(targets: [Target], projectPath: String = "/Project.xcodeproj") -> GeneratedProject {
        var pbxTargets: [String: PBXNativeTarget] = [:]
        targets.forEach { pbxTargets[$0.name] = PBXNativeTarget(name: $0.name) }
        let path = AbsolutePath(projectPath)
        return GeneratedProject(pbxproj: .init(), path: path, targets: pbxTargets, name: path.basename)
    }
}
