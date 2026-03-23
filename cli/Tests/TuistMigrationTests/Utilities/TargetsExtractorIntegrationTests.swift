import Foundation
import Path
import TuistSupport
import Testing

@testable import TuistMigration
@testable import TuistTesting

struct TargetsExtractorIntegrationTests {
    let subject: TargetsExtractor
    init() {
        subject = TargetsExtractor()
    }


    @Test
    func test_when_the_xcodeproj_path_doesnt_exist() async throws {
        // Given
        let xcodeprojPath = try AbsolutePath(validating: "/invalid/path.xcodeproj")

        // Then
        await #expect(throws: TargetsExtractorError.missingXcodeProj(xcodeprojPath)) { try await subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath) }
    }

    @Test
    func test_when_existing_xcodeproj_path_with_targets() async throws {
        // Given
        let xcodeprojPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj"))

        // Then
        let result = try await subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        #expect(!result.isEmpty)
    }
}
