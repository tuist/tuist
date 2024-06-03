import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class GraphLinterTests: TuistUnitTestCase {
    var subject: GraphLinter!
    var graphTraverser: MockGraphTraverser!

    override func setUp() {
        super.setUp()
        graphTraverser = MockGraphTraverser()
        subject = GraphLinter(
            projectLinter: MockProjectLinter(),
            staticProductsLinter: MockStaticProductsGraphLinter()
        )
    }

    override func tearDown() {
        subject = nil
        graphTraverser = nil
        super.tearDown()
    }

    func test_lint_when_frameworks_are_missing() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let frameworkAPath = temporaryPath.appending(try RelativePath(validating: "Test/Build/iOS/A.framework"))
        let frameworkBPath = temporaryPath.appending(try RelativePath(validating: "Test/Build/iOS/B.framework"))
        try FileHandler.shared.createFolder(frameworkAPath)
        let graph = Graph.test(dependencies: [
            GraphDependency.testFramework(path: frameworkAPath): Set(),
            GraphDependency.testFramework(path: frameworkBPath): Set(),
        ])
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(
            result
                .contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString)", severity: .error))
        )
    }

    func test_lint_when_packages_and_xcode_10() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let versionStub = Version(10, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)
        let graph = Graph.test(packages: [path: ["package": package]])
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        let reason =
            "The project contains package dependencies but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertTrue(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_packages_and_xcode_11() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let versionStub = Version(11, 0, 0)
        xcodeController.selectedVersionStub = .success(versionStub)
        let graph = Graph.test(packages: [path: ["package": package]])
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        let reason =
            "The project contains package dependencies but the selected version of Xcode is not compatible. Need at least 11 but got \(versionStub)"
        XCTAssertFalse(result.contains(LintingIssue(reason: reason, severity: .error)))
    }

    func test_lint_when_no_version_available() throws {
        // Given
        let path: AbsolutePath = "/project"
        let package = Package.remote(url: "remote", requirement: .branch("master"))
        let error = NSError.test()
        xcodeController.selectedVersionStub = .failure(error)
        let graph = Graph.test(packages: [path: ["package": package]])
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.contains(LintingIssue(reason: "Could not determine Xcode version", severity: .error)))
    }

    func test_lint_when_staticFramework_depends_on_static_products() throws {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticFrameworkA = Target.test(name: "staticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "staticFrameworkB", product: .staticFramework)
        let staticLibrary = Target.test(name: "staticLibrary", product: .staticLibrary)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let project = Project.test(
            path: path,
            name: "projectStaticFramework",
            targets: [staticFrameworkA, staticFrameworkB, staticLibrary]
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([
                .target(name: staticFrameworkA.name, path: path),
                .target(name: staticFrameworkB.name, path: path),
                .target(name: staticLibrary.name, path: path),
            ]),
            .target(name: staticFrameworkA.name, path: path): Set([.target(name: staticFrameworkB.name, path: path)]),
            .target(name: staticFrameworkB.name, path: path): Set([.target(name: staticLibrary.name, path: path)]),
            .target(name: staticLibrary.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_staticLibrary_depends_on_static_products() throws {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticLibraryA = Target.test(name: "staticLibraryA", product: .staticLibrary)
        let staticLibraryB = Target.test(name: "staticLibraryB", product: .staticLibrary)
        let staticFramework = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let project = Project.test(
            path: "/tmp/staticframework",
            name: "projectStaticFramework",
            targets: [staticLibraryA, staticLibraryB, staticFramework]
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([
                .target(name: staticLibraryA.name, path: path),
                .target(name: staticLibraryB.name, path: path),
                .target(name: staticFramework.name, path: path),
            ]),
            .target(name: staticLibraryA.name, path: path): Set([.target(name: staticLibraryB.name, path: path)]),
            .target(name: staticLibraryB.name, path: path): Set([.target(name: staticFramework.name, path: path)]),
            .target(name: staticFramework.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_messagesExtension_depends_on_static_products() throws {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let messagesExtension = Target.test(name: "MessagesExtensions", platform: .iOS, product: .messagesExtension)
        let staticFramework = Target.test(name: "staticFramework", product: .staticFramework)
        let staticLibrary = Target.test(name: "staticLibrary", product: .staticLibrary)

        let project = Project.test(path: "/tmp/app", name: "App", targets: [
            appTarget,
            messagesExtension,
            staticLibrary,
            staticFramework,
        ])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: appTarget.name, path: path): Set([
                .target(name: messagesExtension.name, path: path),
                .target(name: staticLibrary.name, path: path),
                .target(name: staticFramework.name, path: path),
            ]),
            .target(name: messagesExtension.name, path: path): Set([
                .target(name: staticFramework.name, path: path),
                .target(name: staticLibrary.name, path: path),
            ]),
            .target(name: staticFramework.name, path: path): Set([]),
            .target(name: staticLibrary.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_frameworkDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let framework = Target.empty(name: "framework", product: .framework)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: framework.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_applicationDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let application = Target.empty(name: "application", product: .app)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: application.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_xpcCanDependOnAllTypesOfFrameworksAndLibraries() throws {
        // Given
        let path: AbsolutePath = "/project"
        let dynamicFramework = Target.empty(name: "DynamicFramework", destinations: [.mac], product: .framework)
        let dynamicLibrary = Target.empty(name: "DynamicLibrary", destinations: [.mac], product: .dynamicLibrary)
        let staticFramework = Target.empty(name: "StaticFramework", destinations: [.mac], product: .staticFramework)
        let staticLibrary = Target.empty(name: "StaticLibrary", destinations: [.mac], product: .staticLibrary)

        let xpc = Target.empty(name: "xpc", destinations: [.mac], product: .xpc)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: dynamicFramework.name, path: path): Set([]),
            .target(name: dynamicLibrary.name, path: path): Set([]),
            .target(name: staticFramework.name, path: path): Set([]),
            .target(name: staticLibrary.name, path: path): Set([]),
            .target(name: xpc.name, path: path): Set([
                .target(name: dynamicFramework.name, path: path),
                .target(name: dynamicLibrary.name, path: path),
                .target(name: staticFramework.name, path: path),
                .target(name: staticLibrary.name, path: path),
            ]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(result, [])
    }

    func test_lint_testTargetsDependsOnBundle() throws {
        // Given
        let path: AbsolutePath = "/project"
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let unitTests = Target.empty(name: "unitTests", product: .unitTests)
        let uiTests = Target.empty(name: "uiTests", product: .unitTests)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle.name, path: path): Set([]),
            .target(name: unitTests.name, path: path): Set([.target(name: bundle.name, path: path)]),
            .target(name: uiTests.name, path: path): Set([.target(name: bundle.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_staticProductsCanDependOnDynamicFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let staticFramework = Target.empty(name: "StaticFramework", product: .staticFramework)
        let staticLibrary = Target.empty(name: "StaticLibrary", product: .staticLibrary)
        let dynamicFramework = Target.empty(name: "DynamicFramework", product: .framework)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticLibrary.name, path: path): Set([.target(name: dynamicFramework.name, path: path)]),
            .target(name: staticFramework.name, path: path): Set([.target(name: dynamicFramework.name, path: path)]),
            .target(name: dynamicFramework.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_macStaticProductsCantDependOniOSStaticProducts() throws {
        // Given
        let path: AbsolutePath = "/project"
        let macStaticFramework = Target.empty(name: "MacStaticFramework", destinations: .macOS, product: .staticFramework)
        let iosStaticFramework = Target.empty(name: "iOSStaticFramework", destinations: .iOS, product: .staticFramework)
        let iosStaticLibrary = Target.empty(name: "iOSStaticLibrary", destinations: .iOS, product: .staticLibrary)
        let project = Project.empty(path: path, targets: [macStaticFramework, iosStaticLibrary, iosStaticFramework])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: macStaticFramework.name,
                path: path
            ): Set([
                .target(name: iosStaticFramework.name, path: path),
                .target(name: iosStaticLibrary.name, path: path),
            ]),
            .target(name: iosStaticFramework.name, path: path): Set([]),
            .target(name: iosStaticLibrary.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_watch_canDependOnWatchExtension() throws {
        // Given
        let path: AbsolutePath = "/project"
        let watchExtension = Target.empty(name: "WatckExtension", destinations: .watchOS, product: .watch2Extension)
        let watchApp = Target.empty(name: "WatchApp", destinations: .watchOS, product: .watch2App)
        let project = Project.empty(path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_watch_canOnlyDependOnWatchExtension() throws {
        // Given
        let path: AbsolutePath = "/project"
        let invalidDependency = Target.empty(name: "Framework", destinations: .watchOS, product: .framework)
        let watchApp = Target.empty(name: "WatchApp", destinations: .watchOS, product: .watch2App)
        let project = Project.empty(path: path, targets: [invalidDependency, watchApp])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: watchApp.name, path: path): Set([.target(name: invalidDependency.name, path: path)]),
            .target(name: invalidDependency.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertFalse(result.isEmpty)
    }

    func test_lint_when_watchOS_UITests_depends_on_watch2App() throws {
        // Given
        let path: AbsolutePath = "/project"
        let watchApp = Target.empty(
            name: "WatchApp",
            destinations: .watchOS,
            product: .watch2App
        )
        let watchAppTests = Target.empty(
            name: "WatchAppUITests",
            destinations: .watchOS,
            product: .uiTests,
            dependencies: [.target(name: watchApp.name)]
        )
        let project = Project.test(path: path, targets: [watchApp, watchAppTests])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: watchApp.name, path: path): Set([]),
            .target(name: watchAppTests.name, path: path): Set([.target(name: watchApp.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_when_watchOS_UITests_depends_on_staticLibrary() throws {
        // Given
        let path: AbsolutePath = "/project"
        let staticLibrary = Target.empty(
            name: "StaticLibrary",
            destinations: .watchOS,
            product: .staticLibrary
        )
        let watchAppTests = Target.empty(
            name: "WatchAppUITests",
            destinations: .watchOS,
            product: .uiTests,
            dependencies: [.target(name: staticLibrary.name)]
        )
        let project = Project.test(path: path, targets: [staticLibrary, watchAppTests])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticLibrary.name, path: path): Set([]),
            .target(name: watchAppTests.name, path: path): Set([.target(name: staticLibrary.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_when_watchOS_UITests_depends_on_framework() throws {
        // Given
        let path: AbsolutePath = "/project"
        let framework = Target.empty(
            name: "Framework",
            destinations: .watchOS,
            product: .framework
        )
        let watchAppTests = Target.empty(
            name: "WatchAppUITests",
            destinations: .watchOS,
            product: .uiTests,
            dependencies: [.target(name: framework.name)]
        )
        let project = Project.test(path: path, targets: [framework, watchAppTests])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: framework.name, path: path): Set([]),
            .target(name: watchAppTests.name, path: path): Set([.target(name: framework.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_when_watchOS_UITests_depends_on_staticFramework() throws {
        // Given
        let path: AbsolutePath = "/project"
        let staticFramework = Target.empty(
            name: "StaticFramework",
            destinations: .watchOS,
            product: .watch2App
        )
        let watchAppTests = Target.empty(
            name: "WatchAppUITests",
            destinations: .watchOS,
            product: .uiTests,
            dependencies: [.target(name: staticFramework.name)]
        )
        let project = Project.test(path: path, targets: [staticFramework, watchAppTests])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: staticFramework.name, path: path): Set([]),
            .target(name: watchAppTests.name, path: path): Set([.target(name: staticFramework.name, path: path)]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_watch_application() throws {
        // Note: This was introduced in Xcode 14 / watchOS 9
        // watchOS applications can now use the regular application (.app) product identifier

        // Given
        let path: AbsolutePath = "/project"
        let staticFramework = Target.empty(
            name: "StaticFramework",
            destinations: .watchOS,
            product: .staticFramework
        )
        let dynamicFramework = Target.empty(
            name: "DynamicFramework",
            destinations: .watchOS,
            product: .framework
        )
        let watchApplication = Target.empty(
            name: "WatchApp",
            destinations: .watchOS,
            product: .app,
            dependencies: [
                .target(name: staticFramework.name),
                .target(name: dynamicFramework.name),
            ]
        )
        let project = Project.test(path: path, targets: [watchApplication, staticFramework, dynamicFramework])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: watchApplication.name, path: path): [
                .target(name: staticFramework.name, path: path),
                .target(name: dynamicFramework.name, path: path),
            ],
            .target(name: staticFramework.name, path: path): [],
            .target(name: dynamicFramework.name, path: path): [],
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_watch_application_withWidgetExtension() throws {
        // Note: This was introduced in Xcode 14 / watchOS 9
        // watchOS applications can now use WidgetKit extensions

        // Given
        let path: AbsolutePath = "/project"
        let widgetExtension = Target.empty(
            name: "WidgetExtension",
            destinations: .watchOS,
            product: .appExtension // WidgetKit extension targets are `.appExtension` targets with custom info plist key
        )
        let watchApplication = Target.empty(
            name: "WatchApp",
            destinations: .watchOS,
            product: .app,
            dependencies: [
                .target(name: widgetExtension.name),
            ]
        )
        let project = Project.test(path: path, targets: [watchApplication, widgetExtension])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: watchApplication.name, path: path): [
                .target(name: widgetExtension.name, path: path),
            ],
            .target(name: widgetExtension.name, path: path): [],
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_iOSApp_withCompanionWatchApplication() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.empty(
            name: "App",
            destinations: .iOS,
            product: .app,
            dependencies: [
                .target(name: "WatchApp"),
            ]
        )
        let watchApplication = Target.empty(
            name: "WatchApp",
            destinations: .watchOS,
            product: .app
        )
        let project = Project.test(path: path, targets: [app, watchApplication])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): [
                .target(name: watchApplication.name, path: path),
            ],
            .target(name: watchApplication.name, path: path): [],
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_missingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(
            path: projectAPath,
            name: "ProjectA",
            settings: Settings(configurations: customConfigurations)
        )

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(
            path: projectBPath,
            name: "ProjectB",
            settings: Settings(configurations: customConfigurations)
        )

        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(path: "/path/to/c", name: "ProjectC", settings: .default)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]
        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [projectAPath, projectBPath, projectCPath]),
            projects: [
                projectAPath: projectA,
                projectBPath: projectB,
                projectCPath: projectC,
            ],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(result, [
            LintingIssue(
                reason: "The project 'ProjectC' has missing or mismatching configurations. It has [Debug (debug), Release (release)], other projects have [Beta (release), Debug (debug), Release (release), Testing (debug)]",
                severity: .warning
            ),
        ])
    }

    func test_lint_mismatchingProjectConfigurationsFromDependencyProjects() throws {
        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(
            path: projectAPath,
            name: "ProjectA",
            settings: Settings(configurations: customConfigurations)
        )

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(
            path: projectBPath,
            name: "ProjectB",
            settings: Settings(configurations: customConfigurations)
        )

        let mismatchingConfigurations: [BuildConfiguration: Configuration?] = [
            .release("Debug"): nil,
            .release("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(
            path: projectCPath,
            name: "ProjectC",
            settings: Settings(configurations: mismatchingConfigurations)
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [projectAPath]),
            projects: [
                projectAPath: projectA,
                projectBPath: projectB,
                projectCPath: projectC,
            ],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(result, [
            LintingIssue(
                reason: "The project 'ProjectC' has missing or mismatching configurations. It has [Beta (release), Debug (release), Release (release), Testing (release)], other projects have [Beta (release), Debug (debug), Release (release), Testing (debug)]",
                severity: .warning
            ),
        ])
    }

    func test_lint_doesNotFlagDependenciesWithExtraConfigurations() throws {
        // Lower level dependencies could be shared by projects in different workspaces as such
        // it is ok for them to contain more configurations than the entry node projects

        // Given
        let path: AbsolutePath = "/project"
        let customConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetA = Target.empty(name: "TargetA", product: .framework)
        let projectAPath: AbsolutePath = "/path/to/a"
        let projectA = Project.empty(
            path: projectAPath,
            name: "ProjectA",
            settings: Settings(configurations: customConfigurations)
        )

        let targetB = Target.empty(name: "TargetB", product: .framework)
        let projectBPath: AbsolutePath = "/path/to/b"
        let projectB = Project.empty(
            path: projectBPath,
            name: "ProjectB",
            settings: Settings(configurations: customConfigurations)
        )

        let additionalConfigurations: [BuildConfiguration: Configuration?] = [
            .debug("Debug"): nil,
            .debug("Testing"): nil,
            .release("Beta"): nil,
            .release("Release"): nil,
        ]
        let targetC = Target.empty(name: "TargetC", product: .framework)
        let projectCPath: AbsolutePath = "/path/to/c"
        let projectC = Project.empty(
            path: projectCPath,
            name: "ProjectC",
            settings: Settings(configurations: additionalConfigurations)
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: targetA.name, path: projectAPath): Set([.target(name: targetB.name, path: projectBPath)]),
            .target(name: targetB.name, path: projectBPath): Set([.target(name: targetC.name, path: projectCPath)]),
            .target(name: targetC.name, path: projectCPath): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [projectAPath, projectBPath]),
            projects: [
                projectAPath: projectA,
                projectBPath: projectB,
                projectCPath: projectC,
            ],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(result, [])
    }

    func test_lint_valid_watchTargetBundleIdentifiers() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "app"
        )
        let watchApp = Target.test(
            name: "WatchApp",
            platform: .watchOS,
            product: .watch2App,
            bundleId: "app.watchapp"
        )
        let watchExtension = Target.test(
            name: "WatchExtension",
            platform: .watchOS,
            product: .watch2Extension,
            bundleId: "app.watchapp.watchextension"
        )
        let project = Project.test(path: path, targets: [app, watchApp, watchExtension])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: watchApp.name, path: path)]),
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_invalid_watchTargetBundleIdentifiers() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "app"
        )
        let watchApp = Target.test(
            name: "WatchApp",
            platform: .watchOS,
            product: .watch2App,
            bundleId: "watchapp"
        )
        let watchExtension = Target.test(
            name: "WatchExtension",
            platform: .watchOS,
            product: .watch2Extension,
            bundleId: "watchextension"
        )
        let project = Project.test(targets: [app, watchApp, watchExtension])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: watchApp.name, path: path)]),
            .target(name: watchApp.name, path: path): Set([.target(name: watchExtension.name, path: path)]),
            .target(name: watchExtension.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(
                reason: "Watch app 'WatchApp' bundleId: watchapp isn't prefixed with its parent's app 'app' bundleId 'app'",
                severity: .error
            ),
            LintingIssue(
                reason: "Watch extension 'WatchExtension' bundleId: watchextension isn't prefixed with its parent's watch app 'watchapp' bundleId 'watchapp'",
                severity: .error
            ),
        ])
    }

    func test_lint_valid_appClipTargetBundleIdentifiers() throws {
        // Given
        let temporaryPath = try temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(try RelativePath(validating: "entitlements/AppClip.entitlements"))

        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip = Target.test(
            name: "AppClip",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip",
            entitlements: .file(path: entitlementsPath)
        )
        let project = Project.test(path: temporaryPath, targets: [app, appClip])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([]),
        ]

        let graph = Graph.test(
            path: temporaryPath,
            workspace: Workspace.test(projects: [temporaryPath]),
            projects: [temporaryPath: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_invalid_appClipTargetBundleIdentifiers() throws {
        // Given
        let temporaryPath = try temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(try RelativePath(validating: "entitlements/AppClip.entitlements"))

        let app = Target.test(
            name: "TestApp",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip = Target.test(
            name: "TestAppClip",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example1.app.clip",
            entitlements: .file(path: entitlementsPath)
        )
        let project = Project.test(targets: [app, appClip])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([]),
        ]

        let graph = Graph.test(
            path: temporaryPath,
            workspace: Workspace.test(projects: [temporaryPath]),
            projects: [temporaryPath: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(
                reason: "AppClip 'TestAppClip' bundleId: com.example1.app.clip isn't prefixed with its parent's app 'TestApp' bundleId 'com.example.app'",
                severity: .error
            ),
        ])
    }

    func test_lint_when_appclip_is_missing_required_entitlements() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip = Target.test(
            name: "AppClip",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip"
        )
        let project = Project.test(path: path, targets: [app, appClip])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: appClip.name, path: path)]),
            .target(name: appClip.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(
                reason: "An AppClip 'AppClip' requires its Parent Application Identifiers Entitlement to be set",
                severity: .error
            ),
        ])
    }

    func test_lint_when_appclip_entitlements_does_not_exist() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip = Target.test(
            name: "AppClip",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip",
            entitlements: "/entitlements/AppClip.entitlements"
        )
        let project = Project.test(path: path, targets: [app, appClip])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([.target(name: appClip.name, path: path)]),
            .target(name: appClip.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(
                reason: "The entitlements at path '/entitlements/AppClip.entitlements' referenced by target does not exist",
                severity: .error
            ),
        ])
    }

    func test_lint_when_app_contains_more_than_one_appClip() throws {
        // Given
        let temporaryPath = try temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(try RelativePath(validating: "entitlements/AppClip.entitlements"))

        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip1 = Target.test(
            name: "AppClip1",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip1",
            entitlements: .file(path: entitlementsPath)
        )

        let appClip2 = Target.test(
            name: "AppClip2",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip2",
            entitlements: .file(path: entitlementsPath)
        )

        let project = Project.test(path: temporaryPath, targets: [app, appClip1, appClip2])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: app.name,
                path: temporaryPath
            ): Set([
                .target(name: appClip1.name, path: temporaryPath),
                .target(name: appClip2.name, path: temporaryPath),
            ]),
            .target(name: appClip1.name, path: temporaryPath): Set([]),
            .target(name: appClip2.name, path: temporaryPath): Set([]),
        ]

        let graph = Graph.test(
            path: temporaryPath,
            workspace: Workspace.test(projects: [temporaryPath]),
            projects: [temporaryPath: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(got, [
            LintingIssue(
                reason: "Target 'App' at path '\(temporaryPath.pathString)' cannot depend on more than one app clip: AppClip1 and AppClip2",
                severity: .error
            ),
        ])
    }

    func test_lint_when_appClip_has_a_framework_dependency() throws {
        // Given
        let temporaryPath = try temporaryPath()

        try createFiles([
            "entitlements/AppClip.entitlements",
        ])

        let entitlementsPath = temporaryPath.appending(try RelativePath(validating: "entitlements/AppClip.entitlements"))

        let framework = Target.empty(name: "Framework", product: .framework)

        let app = Target.test(
            name: "App",
            product: .app,
            bundleId: "com.example.app"
        )
        let appClip = Target.test(
            name: "AppClip",
            platform: .iOS,
            product: .appClip,
            bundleId: "com.example.app.clip1",
            entitlements: .file(path: entitlementsPath)
        )

        let project = Project.test(path: temporaryPath, targets: [app, appClip, framework])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: temporaryPath): Set([.target(name: appClip.name, path: temporaryPath)]),
            .target(name: appClip.name, path: temporaryPath): Set([.target(name: framework.name, path: temporaryPath)]),
        ]

        let graph = Graph.test(
            path: temporaryPath,
            workspace: Workspace.test(projects: [temporaryPath]),
            projects: [temporaryPath: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_cli_tool_links_dynamic_framework() throws {
        // Given
        let path: AbsolutePath = "/project"
        let tool = Target.test(
            name: "App",
            platform: .macOS,
            product: .commandLineTool,
            bundleId: "com.example.app"
        )
        let dynamic = Target.test(
            name: "Dynamic",
            platform: .macOS,
            product: .framework,
            bundleId: "com.example.dynamic"
        )

        let project = Project.test(path: path, targets: [tool, dynamic])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: tool.name, path: path): Set([.target(name: dynamic.name, path: path)]),
            .target(name: dynamic.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_cli_tool_links_dynamic_library() throws {
        // Given
        let path: AbsolutePath = "/project"
        let tool = Target.test(
            name: "App",
            platform: .macOS,
            product: .commandLineTool,
            bundleId: "com.example.app"
        )
        let dynamic = Target.test(
            name: "Dynamic",
            platform: .macOS,
            product: .dynamicLibrary,
            bundleId: "com.example.dynamic"
        )

        let project = Project.test(path: path, targets: [tool, dynamic])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: tool.name, path: path): Set([.target(name: dynamic.name, path: path)]),
            .target(name: dynamic.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lint_when_cli_tool_links_supported_dependencies() throws {
        // Given
        let path: AbsolutePath = "/project"

        let tool = Target.test(
            name: "App",
            platform: .macOS,
            product: .commandLineTool,
            bundleId: "com.example.app"
        )
        let staticLib = Target.test(
            name: "StaticLib",
            platform: .macOS,
            product: .staticLibrary,
            bundleId: "com.example.staticlib"
        )
        let staticFmwk = Target.test(
            name: "StaticFramework",
            platform: .macOS,
            product: .staticLibrary,
            bundleId: "com.example.staticfmwk"
        )

        let project = Project.test(path: path, targets: [tool, staticLib, staticFmwk])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(
                name: tool.name,
                path: path
            ): Set([.target(name: staticLib.name, path: path), .target(name: staticFmwk.name, path: path)]),
            .target(name: staticLib.name, path: path): Set([]),
            .target(name: staticFmwk.name, path: path): Set([]),
        ]

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintDifferentBundleIdentifiers() {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let frameworkA = Target.test(name: "frameworkA", product: .framework, bundleId: "com.tuist.frameworks.test")
        let frameworkB = Target.test(name: "frameworkB", product: .framework, bundleId: "com.tuist.frameworks.test2")

        let app = Project.test(path: path, name: "App", targets: [appTarget])
        let frameworks1 = Project.test(
            path: "/tmp/frameworks1",
            name: "Frameworks1",
            targets: [frameworkA, frameworkB]
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: path): Set([
                .target(name: frameworkA.name, path: frameworks1.path),
                .target(name: frameworkB.name, path: frameworks1.path),
            ]),
        ]

        let project = Project.test(path: path, targets: [appTarget, frameworkA, frameworkB])

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [path]),
            projects: [path: project],
            dependencies: dependencies
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintBundleIdentifiersShouldIgnoreVariables() {
        // Given
        let path: AbsolutePath = "/project"
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let frameworkA = Target.test(name: "frameworkA", product: .framework, bundleId: "${ANY_VARIABLE}")
        let frameworkB = Target.test(name: "frameworkB", product: .framework, bundleId: "${ANY_VARIABLE}")
        let frameworkC = Target.test(name: "frameworkC", product: .framework, bundleId: "prefix.${ANY_VARIABLE}")
        let frameworkD = Target.test(name: "frameworkD", product: .framework, bundleId: "prefix.${ANY_VARIABLE}")
        let frameworkE = Target.test(name: "frameworkE", product: .framework, bundleId: "${ANY_VARIABLE}.suffix")
        let frameworkF = Target.test(name: "frameworkF", product: .framework, bundleId: "${ANY_VARIABLE}.suffix")

        let project = Project.test(
            path: path,
            name: "App",
            targets: [appTarget, frameworkA, frameworkB, frameworkC, frameworkD, frameworkE, frameworkF]
        )

        let graph = Graph.test(
            path: path,
            workspace: Workspace.test(projects: [project.path]),
            projects: [
                project.path: project,
            ],
            dependencies: [:]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintCodeCoverage_none() {
        // Given
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: .test())

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintCodeCoverage_all() {
        // Given
        let config = Config.test()
        let graphTraverser = GraphTraverser(
            graph: .test(
                workspace: .test(
                    generationOptions: .test(
                        autogeneratedWorkspaceSchemes: .enabled(codeCoverageMode: .all, testingOptions: [])
                    )
                )
            )
        )

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintCodeCoverage_relevant() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let targetA = Target.test(name: "TargetA")
        let targetB = Target.test(name: "TargetB")
        let project = Project.test(
            path: temporaryPath,
            targets: [targetA, targetB],
            schemes: [
                .test(testAction: .test(
                    coverage: true,
                    codeCoverageTargets: [
                        TargetReference(
                            projectPath: temporaryPath,
                            name: "TargetA"
                        ),
                    ]
                )),
            ]
        )

        let graph = Graph.test(
            workspace: .test(
                generationOptions: .test(
                    autogeneratedWorkspaceSchemes: .enabled(codeCoverageMode: .relevant, testingOptions: [])
                )
            ),
            projects: [temporaryPath: project]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintCodeCoverage_relevant_notConfigured() {
        // Given
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: .test(
            workspace: .test(
                generationOptions: .test(
                    autogeneratedWorkspaceSchemes: .enabled(codeCoverageMode: .relevant, testingOptions: [])
                )
            )
        ))

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(
                    reason: "Cannot find any any targets configured for code coverage, perhaps you wanted to use `CodeCoverageMode.all`?",
                    severity: .warning
                ),
            ]
        )
    }

    func test_lintCodeCoverage_targets() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            targets: [
                Target.test(name: "TargetA"),
                Target.test(name: "TargetB"),
            ]
        )
        let graph = Graph.test(
            workspace: .test(
                generationOptions: .test(
                    autogeneratedWorkspaceSchemes: .enabled(
                        codeCoverageMode: .targets([.init(projectPath: project.path, name: "TargetA")]),
                        testingOptions: []
                    )
                )
            ),
            projects: [temporaryPath: project]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEmpty(got)
    }

    func test_lintCodeCoverage_targets_empty() {
        // Given
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: .test(
            workspace: .test(
                generationOptions: .test(
                    autogeneratedWorkspaceSchemes: .enabled(codeCoverageMode: .targets([]), testingOptions: [])
                )
            )
        ))

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(
                    reason: "List of targets for code coverage is empty",
                    severity: .warning
                ),
            ]
        )
    }

    func test_lintCodeCoverage_targets_nonExisting() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let project = Project.test(
            path: temporaryPath,
            targets: [
                Target.test(name: "TargetB"),
                Target.test(name: "TargetC"),
            ]
        )
        let graph = Graph.test(
            workspace: .test(
                generationOptions: .test(
                    autogeneratedWorkspaceSchemes: .enabled(
                        codeCoverageMode: .targets([.init(projectPath: project.path, name: "TargetA")]),
                        testingOptions: []
                    )
                )
            ),
            projects: [temporaryPath: project]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let got = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(
                    reason: "Target 'TargetA' at '\(project.path)' doesn't exist",
                    severity: .error
                ),
            ]
        )
    }

    func test_lint_multiDestinationTarget_validLinks() throws {
        // Given
        let path = try temporaryPath()
        let iOSAndMacTarget = Target.test(name: "IOSAndMacTarget", destinations: [.iPhone, .mac], product: .framework)
        let macOnlyTarget = Target.test(name: "MacOnlyTarget", destinations: [.mac], product: .framework)

        let project = Project.test(
            path: path,
            targets: [
                iOSAndMacTarget,
                macOnlyTarget,
            ]
        )
        let graph = Graph.test(
            projects: [path: project],
            dependencies: [
                .target(name: iOSAndMacTarget.name, path: path): [
                    .target(name: macOnlyTarget.name, path: path),
                ],
                .target(name: macOnlyTarget.name, path: path): [],
            ],
            dependencyConditions: [
                GraphEdge(
                    from: .target(name: iOSAndMacTarget.name, path: path),
                    to: .target(name: macOnlyTarget.name, path: path)
                ): try .test([.macos]),
            ]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_multiDestinationTarget_invalidLinks() throws {
        // Given
        let path = try temporaryPath()
        let iOSAndMacTarget = Target.test(name: "IOSAndMacTarget", destinations: [.iPhone, .mac], product: .framework)
        let watchOnlyTarget = Target.test(name: "WatchOnlyTarget", destinations: [.appleWatch], product: .framework)

        let project = Project.test(
            path: path,
            targets: [
                iOSAndMacTarget,
                watchOnlyTarget,
            ]
        )
        let graph = Graph.test(
            projects: [path: project],
            dependencies: [
                .target(name: iOSAndMacTarget.name, path: path): [
                    .target(name: watchOnlyTarget.name, path: path),
                ],
                .target(name: watchOnlyTarget.name, path: path): [],
            ]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertFalse(results.isEmpty)
    }

    func test_lint_multiDestinationTarget_dependsOnTargetWithFewerSupportedPlatforms() throws {
        // Given
        let path = try temporaryPath()
        let iOSAndMacTarget = Target.test(name: "IOSAndMacTarget", destinations: [.iPhone, .mac], product: .framework)
        let iOSOnlyTarget = Target.test(name: "iOSOnlyTarget", destinations: [.iPhone], product: .framework)

        let iOSApp = Target.test(name: "iOSApp", destinations: [.iPhone], product: .app)
        let watchApp = Target.test(
            name: "WatchApp",
            destinations: [.appleWatch],
            product: .watch2App,
            bundleId: "io.tuist.iOSApp.WatchApp"
        )

        let project = Project.test(
            path: path,
            targets: [
                iOSAndMacTarget,
                iOSOnlyTarget,
                iOSApp,
                watchApp,
            ]
        )
        let graph = Graph.test(
            projects: [path: project],
            dependencies: [
                .target(name: iOSAndMacTarget.name, path: path): [
                    .target(name: iOSOnlyTarget.name, path: path),
                ],
                .target(name: iOSOnlyTarget.name, path: path): [],
                .target(name: iOSApp.name, path: path): [
                    .target(name: watchApp.name, path: path),
                ],
                .target(name: watchApp.name, path: path): [],
            ]
        )
        let config = Config.test()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser, config: config)

        // Then
        XCTAssertEqual(
            results,
            [LintingIssue(
                reason: "Target IOSAndMacTarget which depends on iOSOnlyTarget does not support the required platforms: macos. The dependency on iOSOnlyTarget must have a dependency condition constraining to at most: ios.",
                severity: .error
            )]
        )
    }
}
