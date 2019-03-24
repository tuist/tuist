import Basic
import Foundation
import XCTest
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit

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

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.asString). The path might be wrong or Carthage dependencies not fetched", severity: .warning)))
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

        XCTAssertTrue(result.contains(LintingIssue(reason: "Framework not found at path \(frameworkBPath.asString)", severity: .error)))
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
}
