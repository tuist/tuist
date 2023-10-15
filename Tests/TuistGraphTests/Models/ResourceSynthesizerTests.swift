import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ResourceSynthesizerTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ResourceSynthesizer(
            parser: .coreData,
            parserOptions: ["key": ResourceSynthesizer.Parser.Option(value: "value")],
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
