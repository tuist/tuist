import Foundation
import Testing
import TuistTesting
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

        #expect(try isCodableRoundTripable(profiles))
    }
}
