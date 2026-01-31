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
            .product(.unitTests),
            "product:unit_tests",
        ]

        #expect(try isCodableRoundTripable(queries))
    }

    @Test func stringLiteral_with_product_prefix() throws {
        let query: TargetQuery = "product:unit_tests"
        #expect(query == .product(.unitTests))
    }

    @Test func stringLiteral_with_invalid_product_falls_back_to_named() throws {
        let query: TargetQuery = "product:invalid"
        #expect(query == .named("product:invalid"))
    }
}
