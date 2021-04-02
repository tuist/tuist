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
    
    func test_codable_when_file() {
        XCTAssertCodable(
            ResourceSynthesizer.strings(templatePath: "Path")
        )
    }
    
    func test_codable_when_custom() {
        XCTAssertCodable(
            ResourceSynthesizer.custom(
                path: "Path",
                parser: .json,
                extensions: ["lottie"]
            )
        )
    }
}
