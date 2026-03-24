import Foundation
import Path
import Testing
@testable import XcodeGraph

struct TestableTargetTests {
    @Test func codable_with_deprecated_parallelizable() throws {
        // Given
        let subject = TestableTarget.test(
            target: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            skipped: true,
            parallelizable: true,
            randomExecutionOrdering: true
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TestableTarget.self, from: data)
        #expect(subject == decoded)
    }

    @Test func codable() throws {
        // Given
        let subject = TestableTarget(
            target: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            skipped: true,
            parallelization: .all,
            randomExecutionOrdering: true
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(TestableTarget.self, from: data)
        #expect(subject == decoded)
    }
}
