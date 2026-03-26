
import Command
import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistTesting

final class SwiftPackageManagerInteractorTests: TuistTestCase {
    private var subject: SwiftPackageManagerInteractor!
    private var commandRunner: MockCommandRunning!
    private var fileSystem: FileSysteming!

    override func setUp() {
        super.setUp()
        commandRunner = MockCommandRunning()
        fileSystem = FileSystem()
        subject = SwiftPackageManagerInteractor(
            fileSystem: fileSystem,
            commandRunner: commandRunner
        )
    }

    override func tearDown() {
        commandRunner = nil
        fileSystem = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_addsPackageDependencyManager_withRemotePackageDependency() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let target = anyTarget(dependencies: [
            .package(product: "Example", type: .runtime),
        ])
        let package = Package.remote(url: "http://some.remote/repo.git", requirement: .exact("branch"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [package]
        )
        let graph = Graph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [GraphDependency.packageProduct(path: project.path, product: "Test", type: .runtime): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        let workspacePath = temporaryPath.appending(component: "\(project.name).xcworkspace")
        // TODO: Update mock stubs for CommandRunner
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        XCTAssertTrue(exists)
    }

    func test_generate_addsPackageDependencyManager_withLocalPackageDependency() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let target = anyTarget(dependencies: [
            .package(product: "Example", type: .runtime),
        ])
        let package = try Package.local(path: AbsolutePath(validating: "/Package/"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [package]
        )
        let graph = Graph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [GraphDependency.packageProduct(path: project.path, product: "Test", type: .runtime): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        let workspacePath = temporaryPath.appending(component: "\(project.name).xcworkspace")
        // TODO: Update mock stubs for CommandRunner
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        XCTAssertTrue(exists)
    }

    func test_generate_usesSystemGitCredentials() async throws {
        // Given
        let temporaryPath = try temporaryPath()

        let target = anyTarget(dependencies: [
            .package(product: "Example", type: .runtime),
        ])
        let package = Package.remote(url: "http://some.remote/repo.git", requirement: .exact("branch"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [package]
        )
        let graph = Graph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [GraphDependency.packageProduct(path: project.path, product: "Test", type: .macro): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        let workspacePath = temporaryPath.appending(component: "\(project.name).xcworkspace")
        // TODO: Update mock stubs for CommandRunner
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(
            graphTraverser: graphTraverser,
            workspaceName: workspacePath.basename,
            configGeneratedProjectOptions: .test(
                compatibleXcodeVersions: .all,
                generationOptions: .test(resolveDependenciesWithSystemScm: true)
            )
        )

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        XCTAssertTrue(exists)
    }

    func test_generate_linksRootPackageResolved_before_resolving() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let target = anyTarget(dependencies: [
            .package(product: "Example", type: .runtime),
        ])
        let package = Package.remote(url: "http://some.remote/repo.git", requirement: .exact("branch"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [
                package,
            ]
        )
        let graph = Graph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [GraphDependency.packageProduct(path: project.path, product: "Test", type: .runtime): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        let workspace = Workspace.test(
            name: project.name,
            projects: [project.path]
        )
        let rootPackageResolvedPath = temporaryPath.appending(component: ".package.resolved")
        try await FileSystem().writeText("package", at: rootPackageResolvedPath)

        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")
        // TODO: Update mock stubs for CommandRunner
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let workspacePackageResolvedPath = temporaryPath
            .appending(try RelativePath(validating: "\(workspace.name).xcworkspace/xcshareddata/swiftpm/Package.resolved"))
        let resolvedText = try await FileSystem().readTextFile(at: workspacePackageResolvedPath)
        XCTAssertEqual(resolvedText, "package")
        try await FileSystem().remove(rootPackageResolvedPath)
        try await FileSystem().writeText("changedPackage", at: rootPackageResolvedPath)
        let changedText = try await FileSystem().readTextFile(at: workspacePackageResolvedPath)
        XCTAssertEqual(changedText, "changedPackage")
    }

    func test_generate_doesNotAddPackageDependencyManager() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let target = anyTarget()
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target]
        )
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)

        let workspace = Workspace.test(projects: [project.path])
        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        XCTAssertFalse(exists)
    }

    func test_generate_sets_cloned_source_packages_dir_path() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let spmPath = temporaryPath.appending(component: "spm")
        let target = anyTarget(dependencies: [
            .package(product: "Example", type: .runtime),
        ])
        let package = Package.remote(url: "http://some.remote/repo.git", requirement: .exact("branch"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [package]
        )
        let graph = Graph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [GraphDependency.packageProduct(path: project.path, product: "Test", type: .runtime): Set()]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        let workspacePath = temporaryPath.appending(component: "\(project.name).xcworkspace")
        // TODO: Update mock stubs for CommandRunner
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(
            graphTraverser: graphTraverser,
            workspaceName: workspacePath.basename,
            configGeneratedProjectOptions: .test(generationOptions: .test(
                clonedSourcePackagesDirPath: temporaryPath
                    .appending(component: "spm")
            ))
        )

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        XCTAssertTrue(exists)
    }

    // MARK: - Helpers

    func anyTarget(dependencies: [TargetDependency] = []) -> Target {
        Target.test(
            infoPlist: nil,
            entitlements: nil,
            settings: nil,
            dependencies: dependencies
        )
    }
}
