import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistGenerator

struct CachedModulesDebuggingGraphMapperTests {
    private let subject = CachedModulesDebuggingGraphMapper()

    @Test(.inTemporaryDirectory)
    func map_configuresRunAndTestActionsThatUseCachedModules() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let originalLLDBInitFile = projectPath.appending(components: "Debugger", "custom.lldbinit")
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let cachedUIFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "ui-hash", "UIFeature.xcframework"
        )
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let uiTests = Target.test(name: "AppUITests", product: .uiTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let uiFeature = Target.test(name: "UIFeature", product: .framework)
        let scheme = Scheme.test(
            name: "App Scheme",
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: TestAction.test(
                targets: [
                    TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests")),
                    TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppUITests")),
                ]
            ),
            runAction: RunAction.test(
                customLLDBInitFile: originalLLDBInitFile,
                executable: TargetReference(projectPath: projectPath, name: "App")
            )
        )
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            targets: [app, tests, uiTests, feature, uiFeature],
            schemes: [scheme]
        )
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let cachedUIFramework = GraphDependency.testXCFramework(path: cachedUIFrameworkPath, linking: .dynamic)
        let workspace = Workspace.test(path: projectPath, projects: [projectPath], schemes: [scheme])
        let sourceGraph = Graph.test(
            workspace: workspace,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppUITests", path: projectPath): [.target(name: "UIFeature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
                .target(name: "UIFeature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            workspace: workspace,
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [cachedFramework],
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                .target(name: "AppUITests", path: projectPath): [cachedUIFramework],
                cachedFramework: [],
                cachedUIFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(
            graph: cachedGraph,
            environment: environment
        )

        let mappedScheme = try #require(mappedGraph.projects[projectPath]?.schemes.first)
        let runAction = try #require(mappedScheme.runAction)
        let testAction = try #require(mappedScheme.testAction)
        #expect(runAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(testAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(runAction.preActions.first?.target?.name == "App")
        #expect(testAction.preActions.first?.target?.name == "AppTests")
        #expect(runAction.customLLDBInitFile?.pathString.hasSuffix("-run.lldbinit") == true)
        #expect(testAction.customLLDBInitFile?.pathString.hasSuffix("-test.lldbinit") == true)
        #expect(mappedGraph.workspace.schemes.first?.runAction?.customLLDBInitFile != nil)
        #expect(mappedGraph.workspace.schemes.first?.testAction?.customLLDBInitFile != nil)

        let runFile = try #require(fileDescriptor(at: runAction.customLLDBInitFile, in: sideEffects))
        let runData = try #require(runFile.contents)
        let runContents = try #require(String(data: runData, encoding: .utf8))
        #expect(runContents.contains("command source -s 0 \"\(originalLLDBInitFile.pathString)\""))
        #expect(runContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        #expect(runContents.contains("settings set symbols.use-swift-explicit-module-loader false"))

        let testFile = try #require(fileDescriptor(at: testAction.customLLDBInitFile, in: sideEffects))
        let testData = try #require(testFile.contents)
        let testContents = try #require(String(data: testData, encoding: .utf8))
        #expect(testContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        #expect(testContents.contains(cachedUIFrameworkPath.parentDirectory.pathString))
        #expect(!testContents.contains("command source"))

        let script = try #require(runAction.preActions.first?.scriptText)
        #expect(script.contains("symbols.cas-path"))
        #expect(script.contains("symbols.cas-plugin-path"))
        #expect(script.contains("symbols.cas-plugin-options"))
        #expect(script.contains("target.swift-framework-search-paths"))
        #expect(script.contains("target.swift-module-search-paths"))
        #expect(script.contains("target.swift-extra-clang-flags"))
        #expect(script.contains("/^sdk"))
        #expect(script.contains("symbols.use-swift-explicit-module-loader false"))
    }

    @Test(.inTemporaryDirectory)
    func map_configuresTestActionsUsingCachedModulesFromTestPlans() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let testTarget = TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))
        let scheme = Scheme.test(
            testAction: TestAction.test(
                targets: [],
                testPlans: [TestPlan(
                    path: projectPath.appending(component: "App.xctestplan"),
                    testTargets: [testTarget],
                    isDefault: true
                )]
            ),
            runAction: nil
        )
        let project = Project.test(path: projectPath, targets: [tests, feature], schemes: [scheme])
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        let testAction = try #require(mappedGraph.projects[projectPath]?.schemes.first?.testAction)
        #expect(testAction.preActions.first?.title == "Update Tuist cache debugger settings")
        #expect(testAction.preActions.first?.target == testTarget.target)
        let testFile = try #require(fileDescriptor(at: testAction.customLLDBInitFile, in: sideEffects))
        let testData = try #require(testFile.contents)
        let testContents = try #require(String(data: testData, encoding: .utf8))
        #expect(testContents.contains(cachedFrameworkPath.parentDirectory.pathString))
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureRunActionUsingCachedModulesFromALaterBuildTarget() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let primaryApp = Target.test(name: "PrimaryApp", product: .app)
        let secondaryApp = Target.test(name: "SecondaryApp", product: .app)
        let feature = Target.test(name: "Feature", product: .framework)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [
                TargetReference(projectPath: projectPath, name: "PrimaryApp"),
                TargetReference(projectPath: projectPath, name: "SecondaryApp"),
            ]),
            testAction: nil,
            runAction: RunAction.test(
                executable: nil,
                expandVariableFromTarget: TargetReference(projectPath: projectPath, name: "SecondaryApp")
            )
        )
        let project = Project.test(
            path: projectPath,
            targets: [primaryApp, secondaryApp, feature],
            schemes: [scheme]
        )
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "PrimaryApp", path: projectPath): [],
                .target(name: "SecondaryApp", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "PrimaryApp", path: projectPath): [],
                .target(name: "SecondaryApp", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        #expect(mappedGraph.projects[projectPath]?.schemes.first?.runAction?.customLLDBInitFile == nil)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureActionsWhenDebuggerAttachmentIsDisabled() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let cachedFrameworkPath = projectPath.appending(
            components: ".tuist-cache", "hash", "Feature.xcframework"
        )
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: TestAction.test(
                targets: [TestableTarget(target: TargetReference(projectPath: projectPath, name: "AppTests"))],
                attachDebugger: false
            ),
            runAction: RunAction.test(
                attachDebugger: false,
                executable: TargetReference(projectPath: projectPath, name: "App")
            )
        )
        let project = Project.test(path: projectPath, targets: [app, tests, feature], schemes: [scheme])
        let cachedFramework = GraphDependency.testXCFramework(path: cachedFrameworkPath, linking: .dynamic)
        let sourceGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "AppTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
                .target(name: "Feature", path: projectPath): [],
            ]
        )
        let cachedGraph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [cachedFramework],
                .target(name: "AppTests", path: projectPath): [cachedFramework],
                cachedFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = sourceGraph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: cachedGraph, environment: environment)

        #expect(mappedGraph == cachedGraph)
        #expect(sideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func map_doesNotConfigureSchemesForPrecompiledDependenciesThatWereAlreadyInTheSourceGraph() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let frameworkPath = projectPath.appending(components: "Frameworks", "Vendor.xcframework")
        let app = Target.test(name: "App", product: .app)
        let scheme = Scheme.test(
            buildAction: BuildAction(targets: [TargetReference(projectPath: projectPath, name: "App")]),
            testAction: nil,
            runAction: RunAction.test(executable: TargetReference(projectPath: projectPath, name: "App"))
        )
        let project = Project.test(path: projectPath, targets: [app], schemes: [scheme])
        let vendorFramework = GraphDependency.testXCFramework(path: frameworkPath, linking: .dynamic)
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): [vendorFramework],
                vendorFramework: [],
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = graph

        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: environment)

        #expect(mappedGraph == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test func map_doesNothingWithoutTheSourceGraph() async throws {
        let graph = Graph.test()

        let (mappedGraph, sideEffects, _) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        #expect(mappedGraph == graph)
        #expect(sideEffects.isEmpty)
    }

    private func fileDescriptor(
        at path: AbsolutePath?,
        in sideEffects: [SideEffectDescriptor]
    ) -> FileDescriptor? {
        sideEffects.compactMap { sideEffect in
            guard case let .file(file) = sideEffect, file.path == path else { return nil }
            return file
        }.first
    }
}
