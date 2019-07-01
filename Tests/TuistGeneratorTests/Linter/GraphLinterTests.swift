import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class GraphLinterTests: XCTestCase {
    var subject: GraphLinter!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = GraphLinter(fileHandler: fileHandler)
    }

    func test_lint_when_carthage_frameworks_are_missing() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let frameworkAPath = fileHandler.currentPath.appending(RelativePath("Carthage/Build/iOS/A.framework"))
        let frameworkBPath = fileHandler.currentPath.appending(RelativePath("Carthage/Build/iOS/B.framework"))

        try fileHandler.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode(path: frameworkAPath)
        let frameworkB = FrameworkNode(path: frameworkBPath)

        cache.add(precompiledNode: frameworkA)
        cache.add(precompiledNode: frameworkB)

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString). The path might be wrong or Carthage dependencies not fetched", severity: .warning)))
    }

    func test_lint_when_frameworks_are_missing() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let frameworkAPath = fileHandler.currentPath.appending(component: "A.framework")
        let frameworkBPath = fileHandler.currentPath.appending(component: "B.framework")

        try fileHandler.createFolder(frameworkAPath)

        let frameworkA = FrameworkNode(path: frameworkAPath)
        let frameworkB = FrameworkNode(path: frameworkBPath)

        cache.add(precompiledNode: frameworkA)
        cache.add(precompiledNode: frameworkB)

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.pathString)", severity: .error)))
    }

    func test_lint_when_static_product_linked_twice() throws {
        let cache = GraphLoaderCache()

        let appTarget = Target.test(name: "AppTarget", dependencies: [.target(name: "staticFramework"), .target(name: "frameworkA")])
        let frameworkTarget = Target.test(name: "frameworkA", dependencies: [.target(name: "staticFramework")])
        let staticFrameworkTarget = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let projectFramework = Project.test(path: "/tmp/framework", name: "projectFramework", targets: [frameworkTarget])
        let projectStaticFramework = Project.test(path: "/tmp/staticframework", name: "projectStaticFramework", targets: [staticFrameworkTarget])

        let staticFramework = TargetNode(project: projectStaticFramework, target: staticFrameworkTarget, dependencies: [])
        let framework = TargetNode(project: projectFramework, target: frameworkTarget, dependencies: [staticFramework])
        let appTargetNode = TargetNode(project: app, target: appTarget, dependencies: [staticFramework, framework])

        cache.add(project: app)
        cache.add(targetNode: appTargetNode)
        cache.add(targetNode: framework)
        cache.add(targetNode: staticFramework)

        let graph = Graph.test(cache: cache, entryNodes: [appTargetNode, framework, staticFramework])

        let result = subject.lint(graph: graph)

        XCTAssertTrue(result.contains(LintingIssue(reason: "Target staticFramework has been linked against AppTarget and frameworkA, it is a static product so may introduce unwanted side effects.", severity: .warning)))
    }

    func test_lint_when_staticFramework_depends_on_static_products() throws {
        // Given
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticFrameworkA = Target.test(name: "staticFrameworkA", product: .staticFramework)
        let staticFrameworkB = Target.test(name: "staticFrameworkB", product: .staticFramework)
        let staticLibrary = Target.test(name: "staticLibrary", product: .staticLibrary)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let frameworks = Project.test(path: "/tmp/staticframework",
                                      name: "projectStaticFramework",
                                      targets: [staticFrameworkA, staticFrameworkB, staticLibrary])

        let graph = Graph.create(dependencies: [
            (project: app, target: appTarget, dependencies: [staticFrameworkA, staticFrameworkB, staticLibrary]),
            (project: frameworks, target: staticFrameworkA, dependencies: [staticFrameworkB]),
            (project: frameworks, target: staticFrameworkB, dependencies: [staticLibrary]),
            (project: frameworks, target: staticLibrary, dependencies: []),
        ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_staticLibrary_depends_on_static_products() throws {
        // Given
        let appTarget = Target.test(name: "AppTarget", product: .app)
        let staticLibraryA = Target.test(name: "staticLibraryA", product: .staticLibrary)
        let staticLibraryB = Target.test(name: "staticLibraryB", product: .staticLibrary)
        let staticFramework = Target.test(name: "staticFramework", product: .staticFramework)

        let app = Project.test(path: "/tmp/app", name: "App", targets: [appTarget])
        let frameworks = Project.test(path: "/tmp/staticframework",
                                      name: "projectStaticFramework",
                                      targets: [staticLibraryA, staticLibraryB, staticFramework])

        let graph = Graph.create(dependencies: [
            (project: app, target: appTarget, dependencies: [staticLibraryA, staticLibraryB, staticFramework]),
            (project: frameworks, target: staticLibraryA, dependencies: [staticLibraryB]),
            (project: frameworks, target: staticLibraryB, dependencies: [staticFramework]),
            (project: frameworks, target: staticFramework, dependencies: []),
        ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_frameworkDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let framework = Target.empty(name: "framework", product: .framework)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: framework, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_applicationDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let application = Target.empty(name: "application", product: .app)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: application, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_testTargetsDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let unitTests = Target.empty(name: "unitTests", product: .unitTests)
        let uiTests = Target.empty(name: "uiTests", product: .unitTests)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: unitTests, dependencies: [bundle]),
                                     (target: uiTests, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_staticTargetDependsOnBundle() throws {
        // Given
        let bundle = Target.empty(name: "bundle", product: .bundle)
        let staticFramework = Target.empty(name: "staticFramework", product: .staticFramework)
        let staticLibrary = Target.empty(name: "staticLibrary", product: .staticLibrary)
        let graph = Graph.create(project: .empty(),
                                 dependencies: [
                                     (target: bundle, dependencies: []),
                                     (target: staticFramework, dependencies: [bundle]),
                                     (target: staticLibrary, dependencies: [bundle]),
                                 ])

        // When
        let result = subject.lint(graph: graph)

        // Then
        let sortedResults = result.sorted { $0.reason < $1.reason }
        XCTAssertEqual(sortedResults, [
            LintingIssue(reason: "Target staticFramework has a dependency with target bundle of type bundle for platform '[\"iOS\"]' which is invalid or not supported yet.", severity: .error),
            LintingIssue(reason: "Target staticLibrary has a dependency with target bundle of type bundle for platform '[\"iOS\"]' which is invalid or not supported yet.", severity: .error),
        ])
    }
}
