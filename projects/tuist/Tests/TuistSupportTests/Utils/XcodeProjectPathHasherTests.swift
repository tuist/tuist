import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class XcodeProjectPathHasherTests: TuistUnitTestCase {
    func test_hash_for_a_given_project_path() throws {
        // Given
        let hash1 = try XcodeProjectPathHasher.hashString(for: "user/natanrolnik/Sportify/SuperApp.xcodeproj")

        // Then
        XCTAssertEqual(hash1, "axwqfsdudhljkxgesivenmeenval")

        // Given
        let hash2 = try XcodeProjectPathHasher.hashString(for: "user/romainboulay/Briochify/SuperApp.xcworkspace")

        // Then
        XCTAssertEqual(hash2, "esdsxrbrdjnnyraonktyhlvyjfmu")
    }
}
