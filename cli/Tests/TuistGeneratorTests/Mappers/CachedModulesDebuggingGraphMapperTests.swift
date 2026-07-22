import Foundation
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class CachedModulesDebuggingGraphMapperTests: TuistUnitTestCase {
    private var subject: CachedModulesDebuggingGraphMapper!

    override func setUp() {
        super.setUp()
        subject = CachedModulesDebuggingGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_configuresRunAndTestActionsThatUseCachedModules() async throws {
        let projectPath = try temporaryPath()
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

        let mappedScheme = try XCTUnwrap(mappedGraph.projects[projectPath]?.schemes.first)
        let runAction = try XCTUnwrap(mappedScheme.runAction)
        let testAction = try XCTUnwrap(mappedScheme.testAction)
        XCTAssertEqual(runAction.preActions.first?.title, "Update Tuist cache debugger settings")
        XCTAssertEqual(testAction.preActions.first?.title, "Update Tuist cache debugger settings")
        XCTAssertEqual(runAction.preActions.first?.target?.name, "App")
        XCTAssertEqual(testAction.preActions.first?.target?.name, "AppTests")
        XCTAssertTrue(runAction.customLLDBInitFile?.pathString.hasSuffix("-run.lldbinit") == true)
        XCTAssertTrue(testAction.customLLDBInitFile?.pathString.hasSuffix("-test.lldbinit") == true)
        XCTAssertNotNil(mappedGraph.workspace.schemes.first?.runAction?.customLLDBInitFile)
        XCTAssertNotNil(mappedGraph.workspace.schemes.first?.testAction?.customLLDBInitFile)

        let runFile = try XCTUnwrap(fileDescriptor(at: runAction.customLLDBInitFile, in: sideEffects))
        let runContents = try XCTUnwrap(String(data: try XCTUnwrap(runFile.contents), encoding: .utf8))
        XCTAssertTrue(runContents.contains("command source -s 0 \"\(originalLLDBInitFile.pathString)\""))
        XCTAssertTrue(runContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        XCTAssertTrue(runContents.contains("settings set symbols.use-swift-explicit-module-loader false"))

        let testFile = try XCTUnwrap(fileDescriptor(at: testAction.customLLDBInitFile, in: sideEffects))
        let testContents = try XCTUnwrap(String(data: try XCTUnwrap(testFile.contents), encoding: .utf8))
        XCTAssertTrue(testContents.contains(cachedFrameworkPath.parentDirectory.pathString))
        XCTAssertTrue(testContents.contains(cachedUIFrameworkPath.parentDirectory.pathString))
        XCTAssertFalse(testContents.contains("command source"))

        let script = try XCTUnwrap(runAction.preActions.first?.scriptText)
        XCTAssertTrue(script.contains("symbols.cas-path"))
        XCTAssertTrue(script.contains("symbols.cas-plugin-path"))
        XCTAssertTrue(script.contains("symbols.cas-plugin-options"))
        XCTAssertTrue(script.contains("target.swift-framework-search-paths"))
        XCTAssertTrue(script.contains("target.swift-module-search-paths"))
        XCTAssertTrue(script.contains("target.swift-extra-clang-flags"))
        XCTAssertTrue(script.contains("/^sdk"))
        XCTAssertTrue(script.contains("symbols.use-swift-explicit-module-loader false"))
    }

    func test_map_doesNotConfigureRunActionUsingCachedModulesFromALaterBuildTarget() async throws {
        let projectPath = try temporaryPath()
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

        XCTAssertNil(mappedGraph.projects[projectPath]?.schemes.first?.runAction?.customLLDBInitFile)
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_doesNotConfigureActionsWhenDebuggerAttachmentIsDisabled() async throws {
        let projectPath = try temporaryPath()
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

        XCTAssertEqual(mappedGraph, cachedGraph)
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_doesNotConfigureSchemesForPrecompiledDependenciesThatWereAlreadyInTheSourceGraph() async throws {
        let projectPath = try temporaryPath()
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

        XCTAssertEqual(mappedGraph, graph)
        XCTAssertTrue(sideEffects.isEmpty)
    }

    func test_map_doesNothingWithoutTheSourceGraph() async throws {
        let graph = Graph.test()

        let (mappedGraph, sideEffects, _) = try await subject.map(
            graph: graph,
            environment: MapperEnvironment()
        )

        XCTAssertEqual(mappedGraph, graph)
        XCTAssertTrue(sideEffects.isEmpty)
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
