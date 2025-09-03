import Foundation
@testable import ProjectDescription
import XCTest

final class CacheProfilesCodableTests: XCTestCase {
    func test_toJSON() throws {
        let profiles = Tuist.CacheProfiles.profiles(
            [
                "p1": .profile(base: .onlyExternal, targets: ["A", "tag:foo"]),
                "p2": .profile(base: .none, targets: []),
            ],
            default: .allPossible
        )
        XCTAssertCodable(profiles)
    }
}
