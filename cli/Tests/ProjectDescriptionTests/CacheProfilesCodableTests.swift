import Foundation
import XCTest
@testable import ProjectDescription

final class CacheProfilesCodableTests: XCTestCase {
    func test_toJSON() throws {
        let profiles = CacheProfiles.profiles(
            [
                "p1": .profile(.onlyExternal, and: ["A", "tag:foo"]),
                "p2": .profile(.none, and: []),
            ],
            default: .allPossible
        )
        XCTAssertCodable(profiles)
    }
}
