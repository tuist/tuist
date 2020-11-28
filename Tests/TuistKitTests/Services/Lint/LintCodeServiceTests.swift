import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting
@testable import TuistLintCodeTesting

final class LintCodeServiceTests: TuistUnitTestCase {
    private var codeLinter: MockCodeLinter!
    private var manifestLoader: MockManifestLoader!
    private var graphLoader: MockGraphLoader!

    private var subject: LintCodeService!

    override func setUp() {
        super.setUp()

        codeLinter = MockCodeLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockGraphLoader()

        subject = LintCodeService(codeLinter: codeLinter,
                                  manifestLoading: manifestLoader,
                                  graphLoader: graphLoader)
    }

    override func tearDown() {
        subject = nil

        codeLinter = nil
        manifestLoader = nil
        graphLoader = nil

        super.tearDown()
    }

    func test_run_throws_an_error_when_no_manifests_exist() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set() }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString, targetName: nil), LintCodeServiceError.manifestNotFound(path))
    }

    func test_run_throws_an_error_when_target_no_exist() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let target01 = Target.test(name: "Target1")
        let target02 = Target.test(name: "Target2")
        let target03 = Target.test(name: "Target3")
        let graph = Graph.test(targets: [
            "/path1": [.test(target: target01), .test(target: target02), .test(target: target03)],
        ])
        let fakeNoExistTargetName = "Target_999"
        graphLoader.loadWorkspaceStub = { _ in graph }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString, targetName: fakeNoExistTargetName), LintCodeServiceError.targetNotFound(fakeNoExistTargetName))
    }

    func test_run_throws_an_error_when_target_to_lint_has_no_sources() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let target01 = Target.test(name: "Target1", sources: [])
        let target02 = Target.test(name: "Target2", sources: [])
        let target03 = Target.test(name: "Target3", sources: [])
        let graph = Graph.test(
            targets: [
                "/path1": [.test(target: target01), .test(target: target02), .test(target: target03)],
            ]
        )
        graphLoader.loadWorkspaceStub = { _ in graph }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString, targetName: target01.name), LintCodeServiceError.lintableFilesForTargetNotFound(target01.name))
    }

    func test_run_thorws_an_error_when_code_liner_throws_error() throws {
        // Given
        let fakeError = TestError("codeLinterFailed")
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }
        codeLinter.stubbedLintError = fakeError

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString, targetName: nil), fakeError)
    }

    func test_run_lint_workspace() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let target01 = Target.test(sources: [
            SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
        ])
        let target02 = Target.test(sources: [
            SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
        ])
        let target03 = Target.test(sources: [
            SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
        ])
        let graph = Graph.test(
            entryPath: "/rootPath",
            targets: [
                "/path1": [.test(target: target01), .test(target: target02), .test(target: target03)],
            ]
        )
        graphLoader.loadWorkspaceStub = { _ in graph }

        // When
        try subject.run(path: path.pathString, targetName: nil)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(invokedLintParameters?.sources, [
            "/target01/file1.swift",
            "/target01/file2.swift",
            "/target02/file1.swift",
            "/target02/file2.swift",
            "/target02/file3.swift",
            "/target03/file1.swift",
        ])
        XCTAssertEqual(invokedLintParameters?.path, path)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(path.pathString)
        Running code linting
        """)
    }

    func test_run_lint_project() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }

        let target01 = Target.test(sources: [
            SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
        ])
        let target02 = Target.test(sources: [
            SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
        ])
        let target03 = Target.test(sources: [
            SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
        ])
        let graph = Graph.test(
            entryPath: "/rootPath",
            targets: [
                "/path1": [.test(target: target01), .test(target: target02), .test(target: target03)],
            ]
        )
        graphLoader.loadProjectStub = { _ in (graph, Project.test()) }

        // When
        try subject.run(path: path.pathString, targetName: nil)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(invokedLintParameters?.sources, [
            "/target01/file1.swift",
            "/target01/file2.swift",
            "/target02/file1.swift",
            "/target02/file2.swift",
            "/target02/file3.swift",
            "/target03/file1.swift",
        ])
        XCTAssertEqual(invokedLintParameters?.path, path)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading project at \(path.pathString)
        Running code linting
        """)
    }

    func test_run_lint_target() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let target01 = Target.test(name: "Target1", sources: [
            SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
        ])
        let target02 = Target.test(name: "Target2", sources: [
            SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
            SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
        ])
        let target03 = Target.test(name: "Target3", sources: [
            SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
        ])
        let graph = Graph.test(targets: [
            "/path1": [.test(target: target01), .test(target: target02), .test(target: target03)],
        ])
        graphLoader.loadWorkspaceStub = { _ in graph }

        // When
        try subject.run(path: path.pathString, targetName: target01.name)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(invokedLintParameters?.sources, [
            "/target01/file1.swift",
            "/target01/file2.swift",
        ])
        XCTAssertEqual(invokedLintParameters?.path, path)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph
        Loading workspace at \(path.pathString)
        Running code linting
        """)
    }
}
