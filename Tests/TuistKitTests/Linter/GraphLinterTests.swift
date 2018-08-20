import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

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
}
