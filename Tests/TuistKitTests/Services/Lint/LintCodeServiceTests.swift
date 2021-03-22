import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLintingTesting
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class LintCodeServiceTests: TuistUnitTestCase {
    private var codeLinter: MockCodeLinter!
    private var simpleGraphLoader: MockSimpleGraphLoader!
    private var basePath: AbsolutePath!

    private var subject: LintCodeService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        codeLinter = MockCodeLinter()
        simpleGraphLoader = MockSimpleGraphLoader()

        basePath = try temporaryPath()

        subject = LintCodeService(
            codeLinter: codeLinter,
            simpleGraphLoader: simpleGraphLoader
        )
    }

    override func tearDown() {
        subject = nil

        codeLinter = nil
        simpleGraphLoader = nil
        basePath = nil

        super.tearDown()
    }

    func test_run_throws_an_error_when_target_no_exist() throws {
        // Given
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(name: "Target1")
        let target02 = Target.test(name: "Target2")
        let target03 = Target.test(name: "Target3")
        let graph = ValueGraph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        let fakeNoExistTargetName = "Target_999"
        simpleGraphLoader.stubLoadGraph = graph

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: fakeNoExistTargetName, strict: false), LintCodeServiceError.targetNotFound(fakeNoExistTargetName))
    }

    func test_run_throws_an_error_when_target_to_lint_has_no_sources() throws {
        // Given
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(name: "Target1", sources: [])
        let target02 = Target.test(name: "Target2", sources: [])
        let target03 = Target.test(name: "Target3", sources: [])
        let graph = ValueGraph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        simpleGraphLoader.stubLoadGraph = graph

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: target01.name, strict: false), LintCodeServiceError.lintableFilesForTargetNotFound(target01.name))
    }

    func test_run_throws_an_error_when_code_liner_throws_error() throws {
        // Given
        let fakeError = TestError("codeLinterFailed")
        let project = Project.test(path: basePath.appending(component: "test"))
        codeLinter.stubbedLintError = fakeError

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: nil, strict: false), fakeError)
    }

    func test_run_lint_workspace() throws {
        // Given
        let workspace = Workspace.test(path: basePath.appending(component: "test"))
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(
            name: "Target1",
            sources: [
                SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
            ]
        )
        let target02 = Target.test(
            name: "Target2",
            sources: [
                SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
            ]
        )
        let target03 = Target.test(
            name: "Target3",
            sources: [
                SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
            ]
        )
        let graph = ValueGraph.test(
            workspace: workspace,
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        simpleGraphLoader.stubLoadGraph = graph

        // When
        try subject.run(path: workspace.path.pathString, targetName: nil, strict: false)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(
            Set(invokedLintParameters?.sources ?? []),
            [
                "/target01/file1.swift",
                "/target01/file2.swift",
                "/target02/file1.swift",
                "/target02/file2.swift",
                "/target02/file3.swift",
                "/target03/file1.swift",
            ]
        )
        XCTAssertEqual(invokedLintParameters?.path, project.path)
        XCTAssertEqual(invokedLintParameters?.strict, false)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(workspace.path)
        Running code linting
        """)
    }

    func test_run_lint_project() throws {
        // Given
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(
            name: "Target1",
            sources: [
                SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
            ]
        )
        let target02 = Target.test(
            name: "Target2",
            sources: [
                SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
            ]
        )
        let target03 = Target.test(
            name: "Target3",
            sources: [
                SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
            ]
        )
        let graph = ValueGraph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        simpleGraphLoader.stubLoadGraph = graph

        // When
        try subject.run(path: project.path.pathString, targetName: nil, strict: false)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(
            Set(invokedLintParameters?.sources ?? []),
            [
                "/target01/file1.swift",
                "/target01/file2.swift",
                "/target02/file1.swift",
                "/target02/file2.swift",
                "/target02/file3.swift",
                "/target03/file1.swift",
            ]
        )
        XCTAssertEqual(invokedLintParameters?.path, project.path)
        XCTAssertEqual(invokedLintParameters?.strict, false)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(project.path)
        Running code linting
        """)
    }

    func test_run_lint_project_strict() throws {
        // Given
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(
            name: "Target1",
            sources: [
                SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
            ]
        )
        let target02 = Target.test(
            name: "Target2",
            sources: [
                SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
            ]
        )
        let target03 = Target.test(
            name: "Target3",
            sources: [
                SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
            ]
        )
        let graph = ValueGraph.test(
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        simpleGraphLoader.stubLoadGraph = graph

        // When
        try subject.run(path: project.path.pathString, targetName: nil, strict: true)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(
            Set(invokedLintParameters?.sources ?? []),
            [
                "/target01/file1.swift",
                "/target01/file2.swift",
                "/target02/file1.swift",
                "/target02/file2.swift",
                "/target02/file3.swift",
                "/target03/file1.swift",
            ]
        )
        XCTAssertEqual(invokedLintParameters?.path, project.path)
        XCTAssertEqual(invokedLintParameters?.strict, true)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(project.path)
        Running code linting
        """)
    }

    func test_run_lint_target() throws {
        // Given
        let workspace = Workspace.test(path: basePath.appending(component: "test"))
        let project = Project.test(path: basePath.appending(component: "test"))
        let target01 = Target.test(
            name: "Target1",
            sources: [
                SourceFile(path: "/target01/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target01/file2.swift", compilerFlags: nil),
            ]
        )
        let target02 = Target.test(
            name: "Target2",
            sources: [
                SourceFile(path: "/target02/file1.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file2.swift", compilerFlags: nil),
                SourceFile(path: "/target02/file3.swift", compilerFlags: nil),
            ]
        )
        let target03 = Target.test(
            name: "Target3",
            sources: [
                SourceFile(path: "/target03/file1.swift", compilerFlags: nil),
            ]
        )
        let graph = ValueGraph.test(
            workspace: workspace,
            projects: [project.path: project],
            targets: [
                project.path: [
                    target01.name: target01,
                    target02.name: target02,
                    target03.name: target03,
                ],
            ]
        )
        simpleGraphLoader.stubLoadGraph = graph

        // When
        try subject.run(path: workspace.path.pathString, targetName: target01.name, strict: false)

        // Then
        let invokedLintParameters = codeLinter.invokedLintParameters

        XCTAssertEqual(codeLinter.invokedLintCount, 1)
        XCTAssertEqual(invokedLintParameters?.sources, [
            "/target01/file1.swift",
            "/target01/file2.swift",
        ])
        XCTAssertEqual(invokedLintParameters?.path, workspace.path)
        XCTAssertEqual(invokedLintParameters?.strict, false)

        XCTAssertPrinterOutputContains("""
        Loading the dependency graph at \(workspace.path)
        Running code linting
        """)
    }
}
