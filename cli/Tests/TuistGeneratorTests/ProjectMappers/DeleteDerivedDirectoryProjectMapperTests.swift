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
        let moduleMapsDirectory = derivedDirectory.appending(component: Constants.DerivedDirectory.moduleMaps)
        let frameworkSearchPathsDirectory = derivedDirectory.appending(component: Constants.DerivedDirectory.frameworkSearchPaths)
        let projectA = Project.test(path: projectPath)
        try await fileSystem.makeDirectory(at: derivedDirectory)
        try await fileSystem.makeDirectory(at: derivedDirectory.appending(component: "InfoPlists"))
        try await fileSystem.makeDirectory(at: moduleMapsDirectory)
        try await fileSystem.makeDirectory(at: frameworkSearchPathsDirectory)
        try await fileSystem.touch(derivedDirectory.appending(component: "TargetA.modulemap"))
        try await fileSystem.touch(moduleMapsDirectory.appending(component: "TargetA-deps.modulemap"))
        try await fileSystem.touch(moduleMapsDirectory.appending(component: "StaleTarget-deps.modulemap"))
        try await fileSystem.touch(frameworkSearchPathsDirectory.appending(component: "TargetA.resp"))
        try await fileSystem.touch(frameworkSearchPathsDirectory.appending(component: "StaleTarget.resp"))

        // When
        let (_, sideEffects) = try await subject.map(project: projectA)

        // Then
        XCTAssertBetterEqual(
            sideEffects.sorted(by: { $0.description < $1.description }),
            [
                .directory(.init(path: derivedDirectory.appending(component: "InfoPlists"), state: .absent)),
            ].sorted(by: { $0.description < $1.description })
        )
    }
}
