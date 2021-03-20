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
    private var manifestLoader: MockManifestLoader!
    private var graphLoader: MockValueGraphLoader!
    private var modelLoader: MockGeneratorModelLoader!
    private var basePath: AbsolutePath!

    private var subject: LintCodeService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        codeLinter = MockCodeLinter()
        manifestLoader = MockManifestLoader()
        graphLoader = MockValueGraphLoader()
        basePath = try temporaryPath()
        modelLoader = MockGeneratorModelLoader(basePath: basePath)

        subject = LintCodeService(
            codeLinter: codeLinter,
            manifestLoading: manifestLoader,
            modelLoader: modelLoader,
            graphLoader: graphLoader
        )
    }

    override func tearDown() {
        subject = nil

        codeLinter = nil
        manifestLoader = nil
        modelLoader = nil
        graphLoader = nil
        
        basePath = nil

        super.tearDown()
    }

    func test_run_throws_an_error_when_no_manifests_exist() throws {
        // Given
        let path = try temporaryPath()
        manifestLoader.manifestsAtStub = { _ in Set() }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString, targetName: nil, strict: false), LintCodeServiceError.manifestNotFound(path))
    }

    func test_run_throws_an_error_when_target_no_exist() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }
        
        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })
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
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: fakeNoExistTargetName, strict: false), LintCodeServiceError.targetNotFound(fakeNoExistTargetName))
    }

    func test_run_throws_an_error_when_target_to_lint_has_no_sources() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }

        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })
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
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: target01.name, strict: false), LintCodeServiceError.lintableFilesForTargetNotFound(target01.name))
    }

    func test_run_throws_an_error_when_code_liner_throws_error() throws {
        // Given
        let fakeError = TestError("codeLinterFailed")
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }
        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })
        codeLinter.stubbedLintError = fakeError

        // When
        XCTAssertThrowsSpecific(try subject.run(path: project.path.pathString, targetName: nil, strict: false), fakeError)
    }

    func test_run_lint_workspace() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let workspace = Workspace.test(path: basePath.appending(component: "test"))
        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockWorkspace("test", loadClosure: { _ in workspace })
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
        graphLoader.loadWorkspaceStub = { _, _ in graph }
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

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
        Loading the dependency graph
        Loading workspace at \(workspace.path.pathString)
        Running code linting
        """)
    }

    func test_run_lint_project() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }

        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })
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
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

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
        Loading the dependency graph
        Loading project at \(project.path.pathString)
        Running code linting
        """)
    }

    func test_run_lint_project_strict() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.project]) }

        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockProject("test", loadClosure: { _ in project })
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
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

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
        Loading the dependency graph
        Loading project at \(project.path.pathString)
        Running code linting
        """)
    }

    func test_run_lint_target() throws {
        // Given
        manifestLoader.manifestsAtStub = { _ in Set([.workspace]) }

        let workspace = Workspace.test(path: basePath.appending(component: "test"))
        let project = Project.test(path: basePath.appending(component: "test"))
        modelLoader.mockWorkspace("test", loadClosure: { _ in workspace })
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
        graphLoader.loadWorkspaceStub = { _, _ in graph }
        graphLoader.loadProjectStub = { _, _ in (project, graph) }

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
        Loading the dependency graph
        Loading workspace at \(workspace.path.pathString)
        Running code linting
        """)
    }
}
