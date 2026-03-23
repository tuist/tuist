import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct HeadersTests {
    @Test func test_toJSON() throws {
        let subject: Headers = .headers(public: "public", private: "private", project: "project")
        #expect(try isCodableRoundTripable(subject))
    }
}
