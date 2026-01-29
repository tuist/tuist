import Testing
import TuistTesting
import XcodeGraph
@testable import TuistCore

struct TargetQueryTests {
    @Test func stringLiteral_with_tag_prefix() throws {
        let query: TargetQuery = "tag:feature"
        #expect(query == .tagged("feature"))
    }

    @Test func stringLiteral_with_product_prefix() throws {
        let query: TargetQuery = "product:unitTests"
        #expect(query == .product(.unitTests))
    }

    @Test func stringLiteral_with_product_prefix_framework() throws {
        let query: TargetQuery = "product:framework"
        #expect(query == .product(.framework))
    }

    @Test func stringLiteral_with_invalid_product_falls_back_to_named() throws {
        let query: TargetQuery = "product:invalid"
        #expect(query == .named("product:invalid"))
    }

    @Test func stringLiteral_without_prefix() throws {
        let query: TargetQuery = "MyTarget"
        #expect(query == .named("MyTarget"))
    }
}
