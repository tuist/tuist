import Foundation
import Path
import Testing
import TuistCore
import TuistSupport

@testable import TuistAutomation
@testable import TuistTesting

struct XcodeBuildControllerTests {
    @Test func showBuildSettings() async throws {
        // Given
        let target = XcodeBuildTarget.project(
            SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "Frameworks/Frameworks.xcodeproj"))
        )
        let subject = XcodeBuildController()

        // When
        let got = try await subject.showBuildSettings(target, scheme: "iOS", configuration: "Debug", derivedDataPath: nil)

        // Then
        #expect(got.count == 1)
        let buildSettings = try #require(got["iOS"])
        #expect(buildSettings.productName == "iOS")
    }

    @Test func version() async throws {
        // When
        let subject = XcodeBuildController()
        let version = try await subject.version()

        // Then
        #expect(version != nil)
    }
}
