import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class LintProjectServiceTests: TuistUnitTestCase {
    var graphLinter: MockGraphLinter!
    var environmentLinter: MockEnvironmentLinter!
    var configLoader: MockConfigLoader!
    var manifestGraphLoader: MockManifestGraphLoader!
    var subject: LintProjectService!
    var path: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        graphLinter = MockGraphLinter()
        environmentLinter = MockEnvironmentLinter()
        path = try temporaryPath()
        configLoader = MockConfigLoader()
        manifestGraphLoader = MockManifestGraphLoader()
        subject = LintProjectService(
            graphLinter: graphLinter,
            environmentLinter: environmentLinter,
            configLoader: configLoader,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    override func tearDown() {
        graphLinter = nil
        environmentLinter = nil
        path = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_relativePath() throws {
        // Given
        let lintPath = "relative"

        // When
        try subject.run(path: lintPath)

        // Then
        let expectedPath = fileHandler.currentPath.appending(component: "relative")
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(expectedPath)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_there_are_no_issues() throws {
        // Given
        let lintPath = path.appending(component: "test")

        // When
        try subject.run(path: lintPath.pathString)

        // Then
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(lintPath)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_linting_fails() throws {
        // Given
        let lintPath = path.appending(component: "test")
        environmentLinter.lintStub = [LintingIssue(reason: "environment", severity: .error)]
        graphLinter.stubbedLintResult = [LintingIssue(reason: "graph", severity: .error)]

        // Then
        XCTAssertThrowsSpecific(try subject.run(path: lintPath.pathString), LintingError())
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(lintPath)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        """)
        XCTAssertPrinterErrorContains("""
        environment
        graph
        """)
    }
}
