import Foundation
import Path
import Testing
@testable import XcodeGraph

struct TestPlanTests {
    @Test func codable() throws {
        // Given
        let subject = TestPlan(
            path: try AbsolutePath(validating: "/path/to"),
            testTargets: [],
            isDefault: true
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TestPlan.self, from: data)
        #expect(subject == decoded)
    }
}
