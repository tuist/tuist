import Foundation
import Testing
@testable import ProjectDescription

struct CacheProfilesCodableTests {
    @Test func toJSON() throws {
        let profiles = CacheProfiles.profiles(
            [
                "p1": .profile(.onlyExternal, and: ["A", "tag:foo"]),
                "p2": .profile(.none, and: []),
            ],
            default: .allPossible
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(profiles)
        let decoded = try decoder.decode(CacheProfiles.self, from: data)

        #expect(profiles == decoded)
    }
}
