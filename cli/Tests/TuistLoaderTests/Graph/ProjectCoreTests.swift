import TuistConstants
import XcodeGraph
import XCTest
@testable import TuistCore
@testable import TuistTesting

final class ProjectCoreTests: TuistUnitTestCase {
    func test_derivedDirectoryPath_whenExternalProjectUsesCustomSwiftPMScratchDirectory() throws {
        // Given
        let scratchDirectory = try temporaryPath()
            .appending(component: "custom-build")
        let projectPath = scratchDirectory.appending(components: "checkouts", "ExternalDependency")
        let target = Target.test(name: "ExternalTarget")
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "ExternalDependency.xcodeproj"),
            targets: [target],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: scratchDirectory
        )

        // When
        let got = project.derivedDirectoryPath(for: target)

        // Then
        XCTAssertEqual(
            got,
            scratchDirectory.appending(
                components: [
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesTargetDirectory,
                    target.name,
                ]
            )
        )
    }

    func test_derivedDirectoryPath_whenExternalProjectPathContainsUnrelatedCheckoutsDirectory() throws {
        // Given
        let projectPath = try temporaryPath()
            .appending(components: "checkouts", "ExternalDependency")
        let target = Target.test(name: "ExternalTarget")
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            xcodeProjPath: projectPath.appending(component: "ExternalDependency.xcodeproj"),
            targets: [target],
            type: .external(hash: nil),
            swiftPackageManagerScratchDirectory: projectPath.parentDirectory.parentDirectory.appending(component: "custom-build")
        )

        // When
        let got = project.derivedDirectoryPath(for: target)

        // Then
        XCTAssertEqual(
            got,
            projectPath.appending(component: Constants.DerivedDirectory.name)
        )
    }
}
