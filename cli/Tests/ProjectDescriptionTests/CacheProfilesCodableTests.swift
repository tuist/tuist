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
                "p3": .profile(.allPossible, and: ["B"], except: ["C", "tag:exclude"]),
            ],
            default: .allPossible
        )

        #expect(try isCodableRoundTripable(profiles))
    }
}
