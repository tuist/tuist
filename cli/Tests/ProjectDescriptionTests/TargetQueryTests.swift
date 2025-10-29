import Foundation
import Testing
@testable import ProjectDescription

struct TargetQueryTests {
    @Test func toJSON() throws {
        let queries: [TargetQuery] = [
            "A",
            .tagged("foo"),
            "tag:bar",
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(queries)
        let decoded = try decoder.decode([TargetQuery].self, from: data)

        #expect(queries == decoded)
    }
}
