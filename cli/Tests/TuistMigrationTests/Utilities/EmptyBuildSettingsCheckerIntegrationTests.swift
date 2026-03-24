import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistMigration
@testable import TuistTesting

struct EmptyBuildSettingsCheckerIntegrationTests {
    let subject: EmptyBuildSettingsChecker
    init() {
        subject = EmptyBuildSettingsChecker()
    }

    @Test
    func when_the_xcodeproj_path_doesnt_exist() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/invalid/path.xcodeproj")

        // Then
        await #expect(throws: EmptyBuildSettingsCheckerError.missingXcodeProj(xcodeprojPath)) { try await subject.check(
            xcodeprojPath: xcodeprojPath,
            targetName: nil
        ) }
    }

    @Test
    func check_when_non_empty_target_build_settings() async throws {
        try await withMockedDependencies {
            // Given
            let xcodeprojPath = SwiftTestingHelper.fixturePath(
                path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj")
            )

            // Then
            await #expect(throws: EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Debug", "Release"])) {
                try await subject.check(
                    xcodeprojPath: xcodeprojPath,
                    targetName: "iOS"
                )
            }
            TuistTest.expectLogs(
                "The build setting 'DYLIB_CURRENT_VERSION' of build configuration 'Debug' is not empty."
            )
        }
    }

    @Test
    func check_when_non_empty_project_build_settings() async throws {
        try await withMockedDependencies {
            // Given
            let xcodeprojPath = SwiftTestingHelper.fixturePath(
                path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj")
            )

            // Then
            await #expect(throws: EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(["Debug", "Release"])) {
                try await subject.check(
                    xcodeprojPath: xcodeprojPath,
                    targetName: nil
                )
            }
            TuistTest.expectLogs(
                "The build setting 'GCC_WARN_UNUSED_VARIABLE' of build configuration 'Debug' is not empty."
            )
        }
    }
}
