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
    var manifestLoader: MockManifestLoader!
    var graphLoader: MockValueGraphLoader!
    var modelLoader: MockGeneratorModelLoader!
    var configLoader: MockConfigLoader!
    var subject: LintProjectService!
    var path: AbsolutePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        graphLinter = MockGraphLinter()
        environmentLinter = MockEnvironmentLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockValueGraphLoader()
        path = try temporaryPath()
        modelLoader = MockGeneratorModelLoader(basePath: path)
        configLoader = MockConfigLoader()
        subject = LintProjectService(
            graphLinter: graphLinter,
            environmentLinter: environmentLinter,
            manifestLoading: manifestLoader,
            graphLoader: graphLoader,
            modelLoader: modelLoader,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        graphLinter = nil
        environmentLinter = nil
        manifestLoader = nil
        graphLoader = nil
        modelLoader = nil
        path = nil
        subject = nil
        super.tearDown()
    }

    func test_run_throws_an_error_when_no_manifests_exist() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set() }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString), LintProjectServiceError.manifestNotFound(path))
    }

    func test_run_when_there_are_no_issues_and_project_manifest() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }
        let project = Project.test(path: path.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })

        // When
        try subject.run(path: project.path.pathString)

        // Then
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading project at \(project.path.pathString)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_there_are_no_issues_and_workspace_manifest() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }
        let workspace = Workspace.test(path: path.appending(component: "test"))
        modelLoader.mockWorkspace("test", loadClosure: { _ in workspace })

        // When
        try subject.run(path: workspace.path.pathString)

        // Then
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(workspace.path.pathString)
        Running linters
        Linting the environment
        Linting the loaded dependency graph
        No linting issues found
        """)
    }

    func test_run_when_linting_fails() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }
        let workspace = Workspace.test(path: path.appending(component: "test"))
        modelLoader.mockWorkspace("test", loadClosure: { _ in workspace })
        environmentLinter.lintStub = [LintingIssue(reason: "environment", severity: .error)]
        graphLinter.stubbedLintResult = [LintingIssue(reason: "graph", severity: .error)]

        // Then
        XCTAssertThrowsSpecific(try subject.run(path: workspace.path.pathString), LintingError())
        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(workspace.path.pathString)
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
