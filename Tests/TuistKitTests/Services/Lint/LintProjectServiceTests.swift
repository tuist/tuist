import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class LintProjectServiceTests: TuistUnitTestCase {
    var graphLinter: MockGraphLinter!
    var environmentLinter: MockEnvironmentLinter!
    var manifestLoader: MockManifestLoader!
    var graphLoader: MockGraphLoader!
    var subject: LintProjectService!

    override func setUp() {
        graphLinter = MockGraphLinter()
        environmentLinter = MockEnvironmentLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockGraphLoader()
        subject = LintProjectService(graphLinter: graphLinter,
                                     environmentLinter: environmentLinter,
                                     manifestLoading: manifestLoader,
                                     graphLoader: graphLoader)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        graphLinter = nil
        environmentLinter = nil
        manifestLoader = nil
        graphLoader = nil
        subject = nil
    }

    func test_run_throws_an_error_when_no_manifests_exist() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set() }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString), LintProjectServiceError.manifestNotFound(path))
    }

    func test_run_when_there_are_no_issues_and_project_manifest() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }

        // When
        try subject.run(path: path.pathString)

        // Then
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading project at \(path.pathString)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_there_are_no_issues_and_workspace_manifest() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        // When
        try subject.run(path: path.pathString)

        // Then
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(path.pathString)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_linting_fails() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }
        environmentLinter.lintStub = [LintingIssue(reason: "environment", severity: .error)]
        graphLinter.lintStub = [LintingIssue(reason: "graph", severity: .error)]

        // Then
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString), LintingError())
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(path.pathString)
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
