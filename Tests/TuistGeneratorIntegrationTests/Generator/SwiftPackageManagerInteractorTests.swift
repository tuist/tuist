
import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class SwiftPackageManagerInteractorTests: TuistUnitTestCase {
    var subject: SwiftPackageManagerInteractor!

    override func setUp() {
        super.setUp()
        subject = SwiftPackageManagerInteractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_addsPackageDependencyManager() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = anyTarget(dependencies: [
            .package(product: "Example"),
        ])
        let package = Package.remote(url: "http://some.remote/repo.git", requirement: .exact("branch"))
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target],
            packages: [package]
        )
        let graph = ValueGraph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [ValueGraphDependency.packageProduct(path: project.path, product: "Test"): Set()]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        let workspacePath = temporaryPath.appending(component: "\(project.name).xcworkspace")
        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
        try createFiles(["\(workspacePath.basename)/xcshareddata/swiftpm/Package.resolved"])

        // When
        try subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".package.resolved")))
    }

    func test_generate_linksRootPackageResolved_before_resolving() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = anyTarget(dependencies: [
            .package(product: "Example"),
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
        let graph = ValueGraph.test(
            path: project.path,
            packages: [project.path: ["Test": package]],
            dependencies: [ValueGraphDependency.packageProduct(path: project.path, product: "Test"): Set()]
        )
        let graphTraverser = ValueGraphTraverser(graph: graph)

        let workspace = Workspace.test(
            name: project.name,
            projects: [project.path]
        )
        let rootPackageResolvedPath = temporaryPath.appending(component: ".package.resolved")
        try FileHandler.shared.write("package", path: rootPackageResolvedPath, atomically: false)

        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")
        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])

        // When
        try subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        let workspacePackageResolvedPath = temporaryPath.appending(RelativePath("\(workspace.name).xcworkspace/xcshareddata/swiftpm/Package.resolved"))
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(workspacePackageResolvedPath),
            "package"
        )
        try FileHandler.shared.write("changedPackage", path: rootPackageResolvedPath, atomically: false)
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(workspacePackageResolvedPath),
            "changedPackage"
        )
    }

    func test_generate_doesNotAddPackageDependencyManager() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = anyTarget()
        let project = Project.test(
            path: temporaryPath,
            name: "Test",
            settings: .default,
            targets: [target]
        )
        let graph = ValueGraph.test()
        let graphTraverser = ValueGraphTraverser(graph: graph)

        let workspace = Workspace.test(projects: [project.path])
        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")

        // When
        try subject.install(graphTraverser: graphTraverser, workspaceName: workspacePath.basename)

        // Then
        XCTAssertFalse(FileHandler.shared.exists(temporaryPath.appending(component: ".package.resolved")))
    }

    // MARK: - Helpers

    func anyTarget(dependencies: [Dependency] = []) -> Target {
        Target.test(
            infoPlist: nil,
            entitlements: nil,
            settings: nil,
            dependencies: dependencies
        )
    }
}
