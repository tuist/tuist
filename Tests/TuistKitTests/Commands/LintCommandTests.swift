import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class LintCommandTests: TuistUnitTestCase {
    var parser: ArgumentParser!
    var graphLinter: MockGraphLinter!
    var environmentLinter: MockEnvironmentLinter!
    var manifestLoader: MockManifestLoader!
    var graphLoader: MockGraphLoader!
    var subject: LintCommand!

    override func setUp() {
        parser = ArgumentParser.test()
        graphLinter = MockGraphLinter()
        environmentLinter = MockEnvironmentLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockGraphLoader()
        subject = LintCommand(graphLinter: graphLinter,
                              environmentLinter: environmentLinter,
                              manifestLoading: manifestLoader,
                              graphLoader: graphLoader,
                              parser: parser)
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

    func test_command() {
        XCTAssertEqual(LintCommand.command, "lint")
    }

    func test_overview() {
        XCTAssertEqual(LintCommand.overview, "Lints a workspace or a project that check whether they are well configured.")
    }

    func test_run_throws_an_error_when_no_manifests_exist() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set() }
        let result = try parser.parse([LintCommand.command, "--path", path.pathString])

        // When
        XCTAssertThrowsSpecific(try subject.run(with: result), LintCommandError.manifestNotFound(path))
    }

    func test_run_when_there_are_no_issues_and_project_manifest() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }
        let result = try parser.parse([LintCommand.command, "--path", path.pathString])

        // When
        try subject.run(with: result)

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
        let result = try parser.parse([LintCommand.command, "--path", path.pathString])

        // When
        try subject.run(with: result)

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
        let result = try parser.parse([LintCommand.command, "--path", path.pathString])

        // Then
        XCTAssertThrowsSpecific(try subject.run(with: result), LintingError())
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
