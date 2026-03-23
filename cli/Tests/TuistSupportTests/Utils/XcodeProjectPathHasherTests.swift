import Testing
@testable import TuistSupport
@testable import TuistTesting

struct XcodeProjectPathHasherTests {
    @Test
    func test_hash_for_a_given_project_path() throws {
        // Given
        let hash1 = try XcodeProjectPathHasher.hashString(for: "user/natanrolnik/Sportify/SuperApp.xcodeproj")

        // Then
        #expect(hash1 == "axwqfsdudhljkxgesivenmeenval")

        // Given
        let hash2 = try XcodeProjectPathHasher.hashString(for: "user/romainboulay/Briochify/SuperApp.xcworkspace")

        // Then
        #expect(hash2 == "esdsxrbrdjnnyraonktyhlvyjfmu")
    }
}
