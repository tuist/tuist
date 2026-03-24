import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator
@testable import TuistTesting

struct DeleteDerivedDirectoryProjectMapperTests {
    let subject: DeleteDerivedDirectoryProjectMapper
    init() {
        subject = DeleteDerivedDirectoryProjectMapper()
    }

    @Test(.inTemporaryDirectory)
    func map_returns_sideEffectsToDeleteDerivedDirectories() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let projectA = Project.test(path: projectPath)
        try FileHandler.shared.createFolder(derivedDirectory)
        try FileHandler.shared.createFolder(derivedDirectory.appending(component: "InfoPlists"))
        try FileHandler.shared.touch(derivedDirectory.appending(component: "TargetA.modulemap"))

        // When
        let (_, sideEffects) = try await subject.map(project: projectA)

        // Then
        #expect(sideEffects == [
            .directory(.init(path: derivedDirectory.appending(component: "InfoPlists"), state: .absent)),
        ])
    }
}
