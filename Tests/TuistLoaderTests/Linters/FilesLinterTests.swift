import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader

class FilesLinterTests: XCTestCase {
    var subject: FilesLinter!

    override func setUp() {
        super.setUp()
        subject = FilesLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_lint_when_source_and_resources_files_missing() {
        // Given
        let path = try! AbsolutePath(validating: "/Test")

        let targets: [ProjectDescription.Target] = [
            .target(
                name: "TestApp",
                destinations: .iOS,
                product: .app,
                bundleId: "testapp",
                sources: [
                    "Sources/AppDelegate.swift",
                ],
                resources: [
                    "Resources/image.png",
                ]
            ),
        ]
        let project = Project.test(
            name: "Test",
            targets: targets
        )

        let workspace: LoadedWorkspace = .init(
            path: .current,
            workspace: Workspace(name: "Test", projects: []),
            projects: [
                path: project,
            ]
        )

        let graphProject = TuistGraph.Project.test(
            path: path,
            targets: [
                .test(
                    name: "TestApp",
                    platform: .iOS,
                    sources: [],
                    resources: []
                ),
            ]
        )

        // When
        let results = subject.lint(project: workspace, convertedProjects: [graphProject])

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "No files found at: Sources/AppDelegate.swift",
            severity: .warning
        )))

        XCTAssertTrue(results.contains(LintingIssue(
            reason: "No resources found at: Resources/image.png",
            severity: .warning
        )))
    }

    func test_lint_when_sources_and_resources_available() {
        // Given
        let path = try! AbsolutePath(validating: "/Test")

        let targets: [ProjectDescription.Target] = [
            .target(
                name: "TestApp",
                destinations: .iOS,
                product: .app,
                bundleId: "testapp",
                sources: [
                    "Sources/AppDelegate.swift",
                ],
                resources: [
                    "Resources/image.png",
                ]
            ),
        ]
        let project = Project.test(
            name: "Test",
            targets: targets
        )

        let workspace: LoadedWorkspace = .init(
            path: .current,
            workspace: Workspace(name: "Test", projects: []),
            projects: [
                path: project,
            ]
        )

        let graphProject = TuistGraph.Project.test(
            path: path,
            targets: [
                .test(
                    name: "TestApp",
                    platform: .iOS,
                    sources: [
                        .init(path: try! AbsolutePath(validating: "/Sources/AppDelegate.swift")),
                    ],
                    resources: [
                        .init(path: try! AbsolutePath(validating: "/Resources/image.png")),
                    ]
                ),
            ]
        )

        // When
        let results = subject.lint(project: workspace, convertedProjects: [graphProject])

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func test_lint_when_sources_using_glob() {
        // Given
        let path = try! AbsolutePath(validating: "/Test")

        let targets: [ProjectDescription.Target] = [
            .target(
                name: "TestApp",
                destinations: .iOS,
                product: .app,
                bundleId: "testapp",
                sources: [
                    "Sources/**",
                ],
                resources: [
                    "Resources/**",
                ]
            ),
        ]
        let project = Project.test(
            name: "Test",
            targets: targets
        )

        let workspace: LoadedWorkspace = .init(
            path: .current,
            workspace: Workspace(name: "Test", projects: []),
            projects: [
                path: project,
            ]
        )

        let graphProject = TuistGraph.Project.test(
            path: path,
            targets: [
                .test(
                    name: "TestApp",
                    platform: .iOS,
                    sources: [],
                    resources: []
                ),
            ]
        )

        // When
        let results = subject.lint(project: workspace, convertedProjects: [graphProject])

        // Then
        XCTAssertTrue(results.isEmpty)
    }
}
