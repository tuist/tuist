import Foundation
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistTesting

public final class DeleteDerivedDirectoryProjectMapperTests: TuistUnitTestCase {
    var subject: DeleteDerivedDirectoryProjectMapper!

    override public func setUp() {
        super.setUp()
        subject = DeleteDerivedDirectoryProjectMapper()
    }

    override public func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_returns_sideEffectsToDeleteDerivedDirectories() async throws {
        // Given
        let projectPath = try temporaryPath()
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let projectA = Project.test(path: projectPath)
        try await fileSystem.makeDirectory(at: derivedDirectory)
        try await fileSystem.makeDirectory(at: derivedDirectory.appending(component: "InfoPlists"))
        try await fileSystem.touch(derivedDirectory.appending(component: "TargetA.modulemap"))

        // When
        let (_, sideEffects) = try await subject.map(project: projectA)

        // Then
        XCTAssertEqual(sideEffects, [
            .directory(.init(path: derivedDirectory.appending(component: "InfoPlists"), state: .absent)),
        ])
    }

    func test_map_preserves_frameworkSearchPaths_directory() async throws {
        // Given
        let projectPath = try temporaryPath()
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let project = Project.test(path: projectPath)
        try await fileSystem.makeDirectory(at: derivedDirectory)
        try await fileSystem.makeDirectory(at: derivedDirectory.appending(component: "InfoPlists"))
        try await fileSystem.makeDirectory(
            at: derivedDirectory.appending(component: Constants.DerivedDirectory.frameworkSearchPaths)
        )

        // When
        let (_, sideEffects) = try await subject.map(project: project)

        // Then
        // FrameworkSearchPaths holds .resp files written by LinkGenerator before this cleanup runs,
        // so it must be preserved while other derived subdirectories are still deleted.
        XCTAssertEqual(sideEffects, [
            .directory(.init(path: derivedDirectory.appending(component: "InfoPlists"), state: .absent)),
        ])
    }
}
