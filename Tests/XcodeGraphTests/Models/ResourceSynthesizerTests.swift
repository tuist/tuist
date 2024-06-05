import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class ResourceSynthesizerTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ResourceSynthesizer(
            parser: .coreData,
            parserOptions: ["key": "value"],
            extensions: [
                "extension1",
                "extension2",
            ],
            template: .defaultTemplate("template")
        )

        // Then
        XCTAssertCodable(subject)
    }
}
