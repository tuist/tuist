import Foundation
import Testing
@testable import TuistMigration
@testable import TuistTesting

struct EmptyBuildSettingsCheckerErrorTests {
    @Test
    func test_description() {
        #expect(EmptyBuildSettingsCheckerError.missingXcodeProj("/tuist.xcodeproj").description == "Couldn't find Xcode project at path /tuist.xcodeproj.")
        #expect(EmptyBuildSettingsCheckerError.missingProject.description == "The project's pbxproj file contains no projects.")
        #expect(EmptyBuildSettingsCheckerError.targetNotFound("Tuist").description == "Couldn't find target with name 'Tuist' in the project.")
        #expect(EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Tuist"]).description == "The following configurations have non-empty build settings: Tuist")
    }

    @Test
    func test_type() {
        #expect(EmptyBuildSettingsCheckerError.missingXcodeProj("/tuist.xcodeproj").type == .abort)
        #expect(EmptyBuildSettingsCheckerError.missingProject.type == .abort)
        #expect(EmptyBuildSettingsCheckerError.targetNotFound("Tuist").type == .abort)
        #expect(EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Tuist"]).type == .abortSilent)
    }
}
