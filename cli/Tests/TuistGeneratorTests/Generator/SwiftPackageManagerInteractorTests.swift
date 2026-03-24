
import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

@testable import TuistGenerator
@testable import TuistTesting

struct SwiftPackageManagerInteractorTests {
    private let subject: SwiftPackageManagerInteractor
    private let system: MockSystem
    private let fileSystem: FileSysteming
    init() {
        system = MockSystem()
        fileSystem = FileSystem()
        subject = SwiftPackageManagerInteractor(
            fileSystem: fileSystem,
            system: system
        )
    }

    @Test(.inTemporaryDirectory)
    func generate_addsPackageDependencyManager_withRemotePackageDependency() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        #expect(exists)
    }

    @Test(.inTemporaryDirectory)
    func generate_addsPackageDependencyManager_withLocalPackageDependency() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
        try await createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let exists = try await fileSystem.exists(temporaryPath.appending(component: ".package.resolved"))
        #expect(exists)
    }

    @Test(.inTemporaryDirectory)
    func generate_usesSystemGitCredentials() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)

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
        system
            .succeedCommand([
                "xcodebuild",
                "-resolvePackageDependencies",
                "-scmProvider",
                "system",
                "-workspace",
                workspacePath.pathString,
                "-list",
            ])
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
        #expect(exists)
    }

    @Test(.inTemporaryDirectory)
    func generate_linksRootPackageResolved_before_resolving() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        try FileHandler.shared.write("package", path: rootPackageResolvedPath, atomically: false)

        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")
        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])

        // When
        try await subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let workspacePackageResolvedPath = temporaryPath
            .appending(try RelativePath(validating: "\(workspace.name).xcworkspace/xcshareddata/swiftpm/Package.resolved"))
        #expect(try FileHandler.shared.readTextFile(workspacePackageResolvedPath) == "package")
        try FileHandler.shared.write("changedPackage", path: rootPackageResolvedPath, atomically: false)
        #expect(try FileHandler.shared.readTextFile(workspacePackageResolvedPath) == "changedPackage")
    }

    @Test(.inTemporaryDirectory)
    func generate_doesNotAddPackageDependencyManager() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        #expect(!exists)
    }

    @Test(.inTemporaryDirectory)
    func generate_sets_cloned_source_packages_dir_path() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        system.succeedCommand([
            "xcodebuild",
            "-resolvePackageDependencies",
            "-clonedSourcePackagesDirPath",
            "\(spmPath.pathString)/\(project.name)",
            "-workspace",
            workspacePath.pathString,
            "-list",
        ])
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
        #expect(exists)
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
