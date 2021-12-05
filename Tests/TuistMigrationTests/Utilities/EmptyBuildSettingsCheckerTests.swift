import Foundation
import TSCBasic
import XCTest
@testable import TuistMigration
@testable import TuistSupportTesting

final class EmptyBuildSettingsCheckerErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            EmptyBuildSettingsCheckerError.missingXcodeProj("/tuist.xcodeproj").description,
            "Couldn't find Xcode project at path /tuist.xcodeproj."
        )
        XCTAssertEqual(
            EmptyBuildSettingsCheckerError.missingProject.description,
            "The project's pbxproj file contains no projects."
        )
        XCTAssertEqual(
            EmptyBuildSettingsCheckerError.targetNotFound("Tuist").description,
            "Couldn't find target with name 'Tuist' in the project."
        )
        XCTAssertEqual(
            EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Tuist"]).description,
            "The following configurations have non-empty build setttings: Tuist"
        )
    }

    func test_type() {
        XCTAssertEqual(EmptyBuildSettingsCheckerError.missingXcodeProj("/tuist.xcodeproj").type, .abort)
        XCTAssertEqual(EmptyBuildSettingsCheckerError.missingProject.type, .abort)
        XCTAssertEqual(EmptyBuildSettingsCheckerError.targetNotFound("Tuist").type, .abort)
        XCTAssertEqual(EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Tuist"]).type, .abortSilent)
    }
}
