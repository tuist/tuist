import Foundation
import XCTest

@testable import ProjectDescription

final class TestableTargetTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable_withTags() throws {
        // Given
        let subject: TestableTarget = .testableTarget(
            target: .init(projectPath: nil, target: "AppTests"),
            parallelization: .swiftTestingOnly,
            selectedTags: ["contract", ".integration"],
            skippedTags: [".slow"]
        )

        // When
        let encoded = try encoder.encode(subject)
        let decoded = try decoder.decode(TestableTarget.self, from: encoded)

        // Then
        XCTAssertEqual(decoded, subject)
        XCTAssertEqual(decoded.selectedTags, ["contract", ".integration"])
        XCTAssertEqual(decoded.skippedTags, [".slow"])
    }

    func test_tags_defaultToEmpty() {
        // Given / When
        let fromFactory: TestableTarget = .testableTarget(target: .init(projectPath: nil, target: "AppTests"))
        let fromStringLiteral: TestableTarget = "AppTests"

        // Then
        XCTAssertEqual(fromFactory.selectedTags, [])
        XCTAssertEqual(fromFactory.skippedTags, [])
        XCTAssertEqual(fromStringLiteral.selectedTags, [])
        XCTAssertEqual(fromStringLiteral.skippedTags, [])
    }
}
