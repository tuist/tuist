import Basic
import Foundation
import XCTest

@testable import TuistCore
@testable import TuistGenerator
@testable import TuistSupportTesting

class StaticProductsGraphLinterTests: XCTestCase {
    var subject: StaticProductsGraphLinter!

    override func setUp() {
        subject = StaticProductsGraphLinter()
    }

    func test_lint_whenPackageDependencyLinkedTwice() throws {
        // Given
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: "/tmp/app", name: "AppProject", targets: [app])

        let package = PackageProductNode(product: "PackageLibrary", path: "/tmp/packageLibrary")
        let frameworkNode = TargetNode(project: project, target: framework, dependencies: [package])
        let appNode = TargetNode(project: project, target: app, dependencies: [package, frameworkNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(targetNode: appNode)
        cache.add(targetNode: frameworkNode)

        let graph = Graph.test(cache: cache, entryNodes: [appNode, frameworkNode, package])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "PackageLibrary", type: "Package", linkedBy: ["App", "Framework"]),
        ])
    }

    func test_lint_whenPrecompiledStaticLibraryLinkedTwice() throws {
        // Given
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(targets: [app, framework])

        let libraryNode = LibraryNode(path: "/path/to/library", publicHeaders: "/path/to/library/include")
        let frameworkNode = TargetNode(project: project, target: framework, dependencies: [libraryNode])
        let appNode = TargetNode(project: project, target: app, dependencies: [libraryNode, frameworkNode])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        cache.add(targetNode: appNode)
        cache.add(targetNode: frameworkNode)
        cache.add(precompiledNode: libraryNode)

        let graph = Graph.test(cache: cache, entryNodes: [appNode, frameworkNode, libraryNode])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "library", type: "Library", linkedBy: ["App", "Framework"]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_1() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let framework = Target.test(name: "Framework", product: .framework)

        let graph = Graph.create(project: .test(),
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework, framework]),
                                     (target: framework, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: ["App", "Framework"]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveStaticFrameworks() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [frameworkB, app],
                                 dependencies: [
                                     (target: app, dependencies: [staticFrameworkC, frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: [staticFrameworkC]),
                                     (target: staticFrameworkC, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkC", linkedBy: ["App", "FrameworkC"]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveFrameworks() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [frameworkB, frameworkC, app],
                                 dependencies: [
                                     (target: app, dependencies: [staticFrameworkC, frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB, frameworkC]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: [staticFrameworkC]),
                                     (target: staticFrameworkC, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkC", linkedBy: ["App", "FrameworkC"]),
        ])
    }

    func test_lint_whenStaticProductLinkedTwice_transitiveFrameworks_2() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)
        let frameworkD = Target.test(name: "FrameworkD", product: .framework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [app, frameworkD],
                                 dependencies: [
                                     (target: app, dependencies: [frameworkA, staticFrameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB, frameworkC]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkA, dependencies: []),

                                     (target: frameworkD, dependencies: [frameworkC, staticFrameworkA]),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: ["App", "FrameworkC"]),
            warning(product: "StaticFrameworkA", linkedBy: ["FrameworkC", "FrameworkD"]),
        ])
    }

    func test_lint_whenNoStaticProductsLinkedTwice_1() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let framework = Target.test(name: "Framework", product: .framework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [framework, app],
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework, framework]),
                                     (target: framework, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertFalse(results.isEmpty)
    }

    func test_lint_whenNoStaticProductsLinkedTwice_2() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFrameworkA = Target.test(name: "StaticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "StaticFrameworkB", product: .staticFramework)
        let staticFrameworkC = Target.test(name: "StaticFrameworkC", product: .staticFramework)
        let frameworkA = Target.test(name: "FrameworkA", product: .framework)
        let frameworkB = Target.test(name: "FrameworkB", product: .framework)
        let frameworkC = Target.test(name: "FrameworkC", product: .framework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [frameworkB, app],
                                 dependencies: [
                                     (target: app, dependencies: [staticFrameworkB, staticFrameworkA, frameworkA]),
                                     (target: frameworkA, dependencies: [frameworkB]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: []),
                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: [staticFrameworkC]),
                                     (target: staticFrameworkC, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenNoStaticProductLinkedTwice_testTargets() throws {
        // Given
        let app = Target.test(name: "App")
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)

        let graph = Graph.create(project: .test(),
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),
                                     (target: frameworkTests, dependencies: [staticFramework]),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_testTargets() throws {
        // Given
        let app = Target.test(name: "App")
        let framework = Target.test(name: "Framework", product: .framework)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)
        let frameworkTests = Target.test(name: "FrameworkTests", product: .unitTests)

        let graph = Graph.create(project: .test(),
                                 dependencies: [
                                     (target: app, dependencies: []),
                                     (target: framework, dependencies: [staticFramework]),
                                     (target: staticFramework, dependencies: []),

                                     (target: frameworkTests, dependencies: [framework, staticFramework]),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFramework", linkedBy: ["Framework", "FrameworkTests"]),
        ])
    }

    func test_lint_whenNoStaticProductLinkedTwice_hostedTestTargets_1() throws {
        // Given
        let app = Target.test(name: "App")
        let appTestsTarget = Target.test(name: "AppTests", product: .unitTests)
        let staticFramework = Target.test(name: "StaticFramework", product: .staticFramework)

        let graph = Graph.create(project: Project.test(),
                                 entryNodes: [appTestsTarget],
                                 dependencies: [
                                     (target: app, dependencies: [staticFramework]),
                                     (target: appTestsTarget, dependencies: [staticFramework, app]),
                                     (target: staticFramework, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenNoStaticProductLinkedTwice_hostedTestTargets_2() throws {
        // Given
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

        let graph = Graph.create(project: Project.test(),
                                 dependencies: [
                                     (target: app, dependencies: [frameworkA]),
                                     (target: appTests, dependencies: [app]),
                                     (target: appUITests, dependencies: [app]),

                                     (target: frameworkA, dependencies: [frameworkB, staticFrameworkA]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: [staticFrameworkC]),
                                     (target: frameworkTests, dependencies: [frameworkA]),

                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: []),
                                     (target: staticFrameworkC, dependencies: []),

                                     (target: staticFrameworkATests, dependencies: [staticFrameworkA]),
                                     (target: staticFrameworkBTests, dependencies: [staticFrameworkB, frameworkB]),
                                     (target: staticFrameworkCTests, dependencies: [staticFrameworkC, staticFrameworkB]),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_whenStaticProductLinkedTwice_hostedTestTargets_1() throws {
        // Given
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

        let graph = Graph.create(project: Project.test(),
                                 dependencies: [
                                     (target: app, dependencies: [frameworkA]),
                                     (target: appTests, dependencies: [app, staticFrameworkA]),
                                     (target: appUITests, dependencies: [app]),

                                     (target: frameworkA, dependencies: [frameworkB, staticFrameworkA]),
                                     (target: frameworkB, dependencies: [frameworkC]),
                                     (target: frameworkC, dependencies: [staticFrameworkC]),
                                     (target: frameworkTests, dependencies: [frameworkA]),

                                     (target: staticFrameworkA, dependencies: [staticFrameworkB]),
                                     (target: staticFrameworkB, dependencies: []),
                                     (target: staticFrameworkC, dependencies: []),
                                 ])

        // When
        let results = subject.lint(graph: graph)

        // Then
        XCTAssertEqual(results, [
            warning(product: "StaticFrameworkA", linkedBy: ["AppTests", "FrameworkA"]),
            warning(product: "StaticFrameworkB", linkedBy: ["AppTests", "FrameworkA"]),
        ])
    }

    // MARK: - Helpers

    private func warning(product node: String, type: String = "Target", linkedBy: [String]) -> LintingIssue {
        let reason = "\(type) \"\(node)\" has been linked against \(linkedBy), it is a static product so may introduce unwanted side effects."
        return LintingIssue(reason: reason,
                            severity: .warning)
    }
}
