import Foundation
import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistGraphTesting
@testable import TuistSupportTesting

class StaticProductsGraphLinterTests: XCTestCase {
    var subject: StaticProductsGraphLinter!

    override func setUp() {
        super.setUp()
        subject = StaticProductsGraphLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_whenPackageDependencyLinkedTwice() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: "/tmp/app", name: "AppProject")
        let package = Package.remote(url: "https://test.tuist.io", requirement: .branch("main"))
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkDependency, .packageProduct(path: path, product: "Package")]),
            frameworkDependency: Set([.packageProduct(path: path, product: "Package")]),
            .packageProduct(path: path, product: "Package"): Set(),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            packages: [path: ["Package": package]],
            targets: [path: [
                app.name: app,
                framework.name: framework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "Package", type: "Package", linkedBy: [appDependency, frameworkDependency]),
        ])
    }

    func test_lint_whenPrecompiledStaticLibraryLinkedTwice() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(targets: [app, framework])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)
        let libraryDependency = GraphDependency.testLibrary(
            path: "/path/to/library",
            publicHeaders: "/path/to/library/include",
            linking: .static
        )

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkDependency, libraryDependency]),
            frameworkDependency: Set([libraryDependency]),
            libraryDependency: Set(),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                framework.name: framework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "library", type: "Library", linkedBy: [appDependency, frameworkDependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(targets: [app, framework, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkDependency, frameworkDependency]),
            frameworkDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set(),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                framework.name: framework,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: [appDependency, frameworkDependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveStaticFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let project = Project
            .test(targets: [app, staticFrameworkA, staticFrameworkB, staticFrameworkC, frameworkA, frameworkB, frameworkC])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkAdependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let staticFrameworkBdependency = GraphDependency.target(name: staticFrameworkB.name, path: path)
        let staticFrameworkCdependency = GraphDependency.target(name: staticFrameworkC.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkCdependency, frameworkADependency]),
            frameworkADependency: Set([frameworkBDependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([staticFrameworkAdependency]),
            staticFrameworkAdependency: Set([staticFrameworkBdependency]),
            staticFrameworkBdependency: Set([staticFrameworkCdependency]),
            staticFrameworkCdependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkC.name: staticFrameworkC,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkC", linkedBy: [appDependency, frameworkCDependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveFrameworks() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let project = Project
            .test(targets: [app, staticFrameworkA, staticFrameworkB, staticFrameworkC, frameworkA, frameworkB, frameworkC])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkAdependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let staticFrameworkBdependency = GraphDependency.target(name: staticFrameworkB.name, path: path)
        let staticFrameworkCdependency = GraphDependency.target(name: staticFrameworkC.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkCdependency, frameworkADependency]),
            frameworkADependency: Set([frameworkBDependency, frameworkCDependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([staticFrameworkAdependency]),
            staticFrameworkAdependency: Set([staticFrameworkBdependency]),
            staticFrameworkBdependency: Set([staticFrameworkCdependency]),
            staticFrameworkCdependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkC.name: staticFrameworkC,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkC", linkedBy: [appDependency, frameworkCDependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveFrameworks_2() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let frameworkD = Target.test(name: "FrameworkD", product: .framework)
        let project = Project.test(targets: [app, frameworkA, frameworkB, frameworkC, staticFrameworkA])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkAdependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)
        let frameworkDDependency = GraphDependency.target(name: frameworkD.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency, staticFrameworkAdependency]),
            frameworkADependency: Set([frameworkBDependency, frameworkCDependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([staticFrameworkAdependency]),
            staticFrameworkAdependency: Set([]),
            frameworkDDependency: Set([frameworkCDependency, staticFrameworkAdependency]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                staticFrameworkA.name: staticFrameworkA,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
                frameworkD.name: frameworkD,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: [appDependency, frameworkCDependency]),
            warning(product: "StaticFrameworkA", linkedBy: [frameworkCDependency, frameworkDDependency]),
        ])
    }

    func test_lint_whenNoStaticProductsLinkedTwice_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(targets: [app, staticFramework, framework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkDependency, frameworkDependency]),
            frameworkDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                staticFramework.name: staticFramework,
                framework.name: framework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertFalse(results.isEmpty)
    }

    func test_lint_whenNoStaticProductsLinkedTwice_2() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let project = Project
            .test(targets: [app, frameworkA, frameworkB, frameworkC, staticFrameworkA, staticFrameworkB, staticFrameworkC])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)
        let staticFrameworkAdependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let staticFrameworkBdependency = GraphDependency.target(name: staticFrameworkB.name, path: path)
        let staticFrameworkCdependency = GraphDependency.target(name: staticFrameworkC.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkBdependency, staticFrameworkAdependency, frameworkADependency]),
            frameworkADependency: Set([frameworkBDependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([]),
            staticFrameworkAdependency: Set([staticFrameworkBdependency]),
            staticFrameworkBdependency: Set([staticFrameworkCdependency]),
            staticFrameworkCdependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkC.name: staticFrameworkC,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenNoStaticProductLinkedTwice_testTargets() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [app, staticFramework, frameworkTests])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)
        let frameworkTestsDependency = GraphDependency.target(name: frameworkTests.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
            frameworkTestsDependency: Set([staticFrameworkDependency]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                staticFramework.name: staticFramework,
                frameworkTests.name: frameworkTests,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_testTargets_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)
        let project = Project.test(targets: [app, staticFramework, frameworkTests])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)
        let frameworkTestsDependency = GraphDependency.target(name: frameworkTests.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([]),
            frameworkDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
            frameworkTestsDependency: Set([frameworkDependency, staticFrameworkDependency]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                framework.name: framework,
                staticFramework.name: staticFramework,
                frameworkTests.name: frameworkTests,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: [frameworkDependency, frameworkTestsDependency]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_hostedTestTargets_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appTestsTarget = Target.test(name: "AppTests", product: .unitTests)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, appTestsTarget, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appTestsDependency = GraphDependency.target(name: appTestsTarget.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([staticFrameworkDependency]),
            appTestsDependency: Set([staticFrameworkDependency, appDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appTestsTarget.name: appTestsTarget,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenNoStaticProductLinkedTwice_hostedTestTargets_2() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)

        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)

        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let staticFrameworkATests = Target.test(name: "StaticFrameworkATests", product: .unitTests)
        let staticFrameworkBTests = Target.test(name: "StaticFrameworkBTests", product: .unitTests)
        let staticFrameworkCTests = Target.test(name: "StaticFrameworkCTests", product: .unitTests)

        let project = Project.test(targets: [
            app,
            appTests,
            appUITests,
            frameworkA,
            frameworkB,
            frameworkC,
            frameworkTests,
            staticFrameworkA,
            staticFrameworkB,
            staticFrameworkC,
            staticFrameworkATests,
            staticFrameworkBTests,
            staticFrameworkCTests,
        ])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appTestsDependency = GraphDependency.target(name: appTests.name, path: path)
        let appUITestsDependency = GraphDependency.target(name: appUITests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)
        let frameworkTestsDependency = GraphDependency.target(name: frameworkTests.name, path: path)

        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let staticFrameworkBDependency = GraphDependency.target(name: staticFrameworkB.name, path: path)
        let staticFrameworkCDependency = GraphDependency.target(name: staticFrameworkC.name, path: path)
        let staticFrameworkATestsDependency = GraphDependency.target(name: staticFrameworkATests.name, path: path)
        let staticFrameworkBTestsDependency = GraphDependency.target(name: staticFrameworkBTests.name, path: path)
        let staticFrameworkCTestsDependency = GraphDependency.target(name: staticFrameworkCTests.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency]),
            appTestsDependency: Set([appDependency]),
            appUITestsDependency: Set([appDependency]),
            frameworkADependency: Set([frameworkBDependency, staticFrameworkADependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([staticFrameworkCDependency]),
            frameworkTestsDependency: Set([frameworkADependency]),
            staticFrameworkADependency: Set([staticFrameworkBDependency]),
            staticFrameworkBDependency: Set(),
            staticFrameworkCDependency: Set(),
            staticFrameworkATestsDependency: Set([staticFrameworkADependency]),
            staticFrameworkBTestsDependency: Set([staticFrameworkBDependency, frameworkBDependency]),
            staticFrameworkCTestsDependency: Set([staticFrameworkCDependency, staticFrameworkBDependency]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appTests.name: appTests,
                appUITests.name: appUITests,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
                frameworkTests.name: frameworkTests,
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkC.name: staticFrameworkC,
                staticFrameworkATests.name: staticFrameworkATests,
                staticFrameworkBTests.name: staticFrameworkBTests,
                staticFrameworkCTests.name: staticFrameworkCTests,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_hostedTestTargets_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appTests = Target.test(name: "AppTests", product: .unitTests)

        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)

        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)

        let project = Project.test(targets: [
            app,
            appTests,
            frameworkA,
            frameworkB,
            frameworkC,
            frameworkTests,
            staticFrameworkA,
            staticFrameworkB,
            staticFrameworkC,
        ])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appTestsDependency = GraphDependency.target(name: appTests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let frameworkBDependency = GraphDependency.target(name: frameworkB.name, path: path)
        let frameworkCDependency = GraphDependency.target(name: frameworkC.name, path: path)
        let frameworkTestsDependency = GraphDependency.target(name: frameworkTests.name, path: path)

        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)
        let staticFrameworkBDependency = GraphDependency.target(name: staticFrameworkB.name, path: path)
        let staticFrameworkCDependency = GraphDependency.target(name: staticFrameworkC.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency]),
            appTestsDependency: Set([appDependency, staticFrameworkADependency]),
            frameworkADependency: Set([frameworkBDependency, staticFrameworkADependency]),
            frameworkBDependency: Set([frameworkCDependency]),
            frameworkCDependency: Set([staticFrameworkCDependency]),
            frameworkTestsDependency: Set([frameworkADependency]),
            staticFrameworkADependency: Set([staticFrameworkBDependency]),
            staticFrameworkBDependency: Set(),
            staticFrameworkCDependency: Set(),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appTests.name: appTests,
                frameworkA.name: frameworkA,
                frameworkB.name: frameworkB,
                frameworkC.name: frameworkC,
                frameworkTests.name: frameworkTests,
                staticFrameworkA.name: staticFrameworkA,
                staticFrameworkB.name: staticFrameworkB,
                staticFrameworkC.name: staticFrameworkC,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: [appTestsDependency, frameworkADependency]),
            warning(product: "StaticFrameworkB", linkedBy: [appTestsDependency, frameworkADependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_hostedTestTargets_2() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)

        let project = Project.test(targets: [app, appTests, appUITests, frameworkA, staticFrameworkA])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appTestsDependency = GraphDependency.target(name: appTests.name, path: path)
        let appUITestsDependency = GraphDependency.target(name: appUITests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency]),
            appTestsDependency: Set([appDependency, staticFrameworkADependency]),
            appUITestsDependency: Set([appDependency, frameworkADependency, staticFrameworkADependency]),
            frameworkADependency: Set([staticFrameworkADependency]),
            staticFrameworkADependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appTests.name: appTests,
                appUITests.name: appUITests,
                frameworkA.name: frameworkA,
                staticFrameworkA.name: staticFrameworkA,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: [appTestsDependency, frameworkADependency]),
            warning(product: "StaticFrameworkA", linkedBy: [appUITestsDependency, frameworkADependency]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_uiTestTargets() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let project = Project.test(targets: [app, appUITests, frameworkA, staticFrameworkA])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appUITestsDependency = GraphDependency.target(name: appUITests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency]),
            appUITestsDependency: Set([appDependency, staticFrameworkADependency]),
            frameworkADependency: Set([staticFrameworkADependency]),
            staticFrameworkADependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appUITests.name: appUITests,
                frameworkA.name: frameworkA,
                staticFrameworkA.name: staticFrameworkA,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then

        // UITest bundles are hosted in a separate app (App-TestRunner) as such
        // it should be treated as a separate graph that isn't connected to the main
        // app's graph. It's an unfortunate side effect of declaring a target application
        // of a UI test bundle as a dependency.
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_uiTestTargets_1() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let project = Project.test(targets: [app, appUITests, frameworkA, staticFrameworkA])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appUITestsDependency = GraphDependency.target(name: appUITests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency]),
            appUITestsDependency: Set([appDependency, staticFrameworkADependency, frameworkADependency]),
            frameworkADependency: Set([staticFrameworkADependency]),
            staticFrameworkADependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appUITests.name: appUITests,
                frameworkA.name: frameworkA,
                staticFrameworkA.name: staticFrameworkA,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: [appUITestsDependency, frameworkADependency]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_uiTestTargets_2() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let project = Project.test(targets: [app, appUITests, frameworkA, staticFrameworkA])

        // App ----> Framework A

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appUITestsDependency = GraphDependency.target(name: appUITests.name, path: path)
        let frameworkADependency = GraphDependency.target(name: frameworkA.name, path: path)
        let staticFrameworkADependency = GraphDependency.target(name: staticFrameworkA.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appDependency: Set([frameworkADependency, staticFrameworkADependency]),
            appUITestsDependency: Set([appDependency, staticFrameworkADependency, frameworkADependency]),
            frameworkADependency: Set([staticFrameworkADependency]),
            staticFrameworkADependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appUITests.name: appUITests,
                frameworkA.name: frameworkA,
                staticFrameworkA.name: staticFrameworkA,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: [appUITestsDependency, frameworkADependency]),
            warning(product: "StaticFrameworkA", linkedBy: [appDependency, frameworkADependency]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_extensions() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, appExtension, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appExtensionDependency = GraphDependency.target(name: appExtension.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle extensions via dependencies
            appDependency: Set([staticFrameworkDependency, appExtensionDependency]),
            appExtensionDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appExtension.name: appExtension,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_extensions() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let framework = Target.test(name: "Framework", product: .framework)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, appExtension, framework, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appExtensionDependency = GraphDependency.target(name: appExtension.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle extensions via dependencies
            appDependency: Set([staticFrameworkDependency, appExtensionDependency]),
            appExtensionDependency: Set([staticFrameworkDependency, frameworkDependency]),
            frameworkDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appExtension.name: appExtension,
                staticFramework.name: staticFramework,
                framework.name: framework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: [appExtensionDependency, frameworkDependency]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_appClips() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appClip = Target.test(name: "WatchApp", product: .appClip)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, appClip, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appClipDependency = GraphDependency.target(name: appClip.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle app clips via dependencies
            appDependency: Set([staticFrameworkDependency, appClipDependency]),
            appClipDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appClip.name: appClip,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_appClips() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App")
        let appClip = Target.test(name: "AppClip", product: .appClip)
        let framework = Target.test(name: "Framework", product: .framework)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let project = Project.test(targets: [app, appClip, framework, staticFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let appClipDependency = GraphDependency.target(name: appClip.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)
        let staticFrameworkDependency = GraphDependency.target(name: staticFramework.name, path: path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle app clips via dependencies
            appDependency: Set([staticFrameworkDependency, appClipDependency]),
            appClipDependency: Set([frameworkDependency, staticFrameworkDependency]),
            frameworkDependency: Set([staticFrameworkDependency]),
            staticFrameworkDependency: Set([]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                appClip.name: appClip,
                framework.name: framework,
                staticFramework.name: staticFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: [appClipDependency, frameworkDependency]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_swiftPackagesAndWatchAppExtensions() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let watchAppExtension = Target.test(name: "WatchAppExtension", platform: .watchOS, product: .watch2Extension)
        let project = Project.test(targets: [app, watchApp, watchAppExtension])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let watchAppDependency = GraphDependency.target(name: watchApp.name, path: path)
        let watchAppExtensionDependency = GraphDependency.target(name: watchAppExtension.name, path: path)
        let swiftPackage = GraphDependency.packageProduct(path: "/path/to/package", product: "LocalPackage")

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle watch apps via dependencies
            appDependency: Set([swiftPackage, watchAppDependency]),
            // apps declare they bundle extensions via dependencies
            watchAppDependency: Set([watchAppExtensionDependency]),
            watchAppExtensionDependency: Set([swiftPackage]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                watchApp.name: watchApp,
                watchAppExtension.name: watchAppExtension,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_swiftPackagesAndWatchAppExtensions() throws {
        // Given
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", platform: .iOS, product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let watchAppExtension = Target.test(name: "WatchAppExtension", platform: .watchOS, product: .watch2Extension)
        let watchFramework = Target.test(name: "WatchFramework", platform: .watchOS, product: .framework)
        let project = Project.test(targets: [app, watchApp, watchAppExtension, watchFramework])

        let appDependency = GraphDependency.target(name: app.name, path: path)
        let watchAppDependency = GraphDependency.target(name: watchApp.name, path: path)
        let watchAppExtensionDependency = GraphDependency.target(name: watchAppExtension.name, path: path)
        let watchFrameworkDependency = GraphDependency.target(name: watchFramework.name, path: path)
        let swiftPackage = GraphDependency.packageProduct(path: "/path/to/package", product: "LocalPackage")

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            // apps declare they bundle watch apps via dependencies
            appDependency: Set([swiftPackage, watchAppDependency]),
            // apps declare they bundle extensions via dependencies
            watchAppDependency: Set([watchAppExtensionDependency]),
            watchAppExtensionDependency: Set([swiftPackage, watchFrameworkDependency]),
            watchFrameworkDependency: Set([swiftPackage]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            targets: [path: [
                app.name: app,
                watchApp.name: watchApp,
                watchAppExtension.name: watchAppExtension,
                watchFramework.name: watchFramework,
            ]],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let results = subject.lint(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(results, [
            warning(product: "LocalPackage", type: "Package", linkedBy: [watchAppExtensionDependency, watchFrameworkDependency]),
        ])
    }

    // MARK: - Helpers

    private func warning(product node: String, type: String = "Target", linkedBy: [GraphDependency]) -> LintingIssue {
        let reason =
            "\(type) \'\(node)\' has been linked from \(linkedBy.map(\.description).listed()), it is a static product so may introduce unwanted side effects."
                .uppercasingFirst
        return LintingIssue(
            reason: reason,
            severity: .warning
        )
    }
}
