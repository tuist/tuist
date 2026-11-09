import Foundation
import Testing
import TuistTesting
@testable import ProjectDescription

struct TargetQueryTests {
    @Test func toJSON() throws {
        let queries: [TargetQuery] = [
            "A",
            .tagged("foo"),
            "tag:bar",
        ]

        #expect(try isCodableRoundTripable(queries))
    }
}
