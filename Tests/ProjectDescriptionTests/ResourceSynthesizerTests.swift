import Foundation
import XCTest

@testable import ProjectDescription

final class ResourceSynthesizerTests: XCTestCase {
    func test_codable_when_plugin() {
        XCTAssertCodable(
            ResourceSynthesizer.assets(plugin: "Plugin")
        )
    }

    func test_codable_when_default() {
        XCTAssertCodable(
            ResourceSynthesizer.strings()
        )
    }

    func test_codable_when_parserOptions() {
        XCTAssertCodable(
            ResourceSynthesizer.strings(parserOptions: ["separator": .stringValue("/")])
        )
    }

    func test_codable_when_custom() {
        XCTAssertCodable(
            ResourceSynthesizer.custom(
                name: "Custom",
                parser: .json,
                parserOptions: ["key": .stringValue("value")],
                extensions: ["lottie"]
            )
        )
    }
}
