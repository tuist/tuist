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
            .matching(pattern: "*-UnitTests"),
            "*-ScreenshotTests",
        ]

        #expect(try isCodableRoundTripable(queries))
    }

    @Test func stringLiteralWithoutWildcardsIsAName() {
        let query: TargetQuery = "App"
        #expect(query == .named("App"))
    }

    @Test func stringLiteralWithTagPrefixIsATag() {
        let query: TargetQuery = "tag:unit-tests"
        #expect(query == .tagged("unit-tests"))
    }

    @Test func stringLiteralWithWildcardsIsAPattern() {
        let patterns: [TargetQuery] = ["*-UnitTests", "Feature?", "[AB]pp"]
        #expect(patterns == [
            .matching(pattern: "*-UnitTests"),
            .matching(pattern: "Feature?"),
            .matching(pattern: "[AB]pp"),
        ])
    }
}
