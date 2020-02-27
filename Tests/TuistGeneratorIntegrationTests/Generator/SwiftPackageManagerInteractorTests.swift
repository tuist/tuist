
import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class SwiftPackageManagerInteractorTests: TuistUnitTestCase {
    //    func test_generate_addsPackageDependencyManager() throws {
    //        // Given
    //        let temporaryPath = try self.temporaryPath()
    //        let target = anyTarget(dependencies: [
    //            .package(product: "Example"),
    //        ])
    //        let project = Project.test(path: temporaryPath,
    //                                   name: "Test",
    //                                   settings: .default,
    //                                   targets: [target],
    //                                   packages: [
    //                                       .remote(url: "http://some.remote/repo.git", requirement: .exact("branch")),
    //                                   ])
    //        let graph = Graph.create(project: project,
    //                                 dependencies: [(target, [])])
    //
    //        let workspace = Workspace.test(name: project.name,
    //                                       projects: [project.path])
    //        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")
    //        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
    //        try createFiles(["\(workspace.name).xcworkspace/xcshareddata/swiftpm/Package.resolved"])
    //
    //        // When
    //        try subject.generate(workspace: workspace,
    //                             path: temporaryPath,
    //                             graph: graph)
    //
    //        // Then
    //        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".package.resolved")))
    //
    //        XCTAssertNoThrow(try subject.generate(workspace: workspace,
    //                                              path: temporaryPath,
    //                                              graph: graph))
    //    }

    //    func test_generate_linksRootPackageResolved_before_resolving() throws {
    //        // Given
    //        let temporaryPath = try self.temporaryPath()
    //        let target = anyTarget(dependencies: [
    //            .package(product: "Example"),
    //        ])
    //        let project = Project.test(path: temporaryPath,
    //                                   name: "Test",
    //                                   settings: .default,
    //                                   targets: [target],
    //                                   packages: [
    //                                       .remote(url: "http://some.remote/repo.git", requirement: .exact("branch")),
    //                                   ])
    //        let graph = Graph.create(project: project,
    //                                 dependencies: [(target, [])])
    //
    //        let workspace = Workspace.test(name: project.name,
    //                                       projects: [project.path])
    //        let rootPackageResolvedPath = temporaryPath.appending(component: ".package.resolved")
    //        try FileHandler.shared.write("package", path: rootPackageResolvedPath, atomically: false)
    //
    //        let workspacePath = temporaryPath.appending(component: workspace.name + ".xcworkspace")
    //        system.succeedCommand(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
    //
    //        // When
    //        try subject.generate(workspace: workspace,
    //                             path: temporaryPath,
    //                             graph: graph)
    //
    //        // Then
    //        let workspacePackageResolvedPath = temporaryPath.appending(RelativePath("\(workspace.name).xcworkspace/xcshareddata/swiftpm/Package.resolved"))
    //        XCTAssertEqual(
    //            try FileHandler.shared.readTextFile(workspacePackageResolvedPath),
    //            "package"
    //        )
    //        try FileHandler.shared.write("changedPackage", path: rootPackageResolvedPath, atomically: false)
    //        XCTAssertEqual(
    //            try FileHandler.shared.readTextFile(workspacePackageResolvedPath),
    //            "changedPackage"
    //        )
    //    }

    //    func test_generate_doesNotAddPackageDependencyManager() throws {
    //        // Given
    //        let temporaryPath = try self.temporaryPath()
    //        let target = anyTarget()
    //        let project = Project.test(path: temporaryPath,
    //                                   name: "Test",
    //                                   settings: .default,
    //                                   targets: [target])
    //        let graph = Graph.create(project: project,
    //                                 dependencies: [(target, [])])
    //
    //        let workspace = Workspace.test(projects: [project.path])
    //
    //        // When
    //        try subject.generate(workspace: workspace,
    //                             path: temporaryPath,
    //                             graph: graph)
    //
    //        // Then
    //        XCTAssertFalse(FileHandler.shared.exists(temporaryPath.appending(component: ".package.resolved")))
    //    }
}
