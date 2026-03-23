import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct ResourceSynthesizerTests {
    @Test func test_codable_when_plugin() throws {
        #expect(try isCodableRoundTripable(
            ResourceSynthesizer.assets(plugin: "Plugin")
        ))
    }

    @Test func test_codable_when_default() throws {
        #expect(try isCodableRoundTripable(
            ResourceSynthesizer.strings()
        ))
    }

    @Test func test_codable_when_parserOptions() throws {
        #expect(try isCodableRoundTripable(
            ResourceSynthesizer.strings(parserOptions: ["separator": "/"])
        ))
    }

    @Test func test_codable_when_custom() throws {
        #expect(try isCodableRoundTripable(
            ResourceSynthesizer.custom(
                name: "Custom",
                parser: .json,
                parserOptions: ["key": "value"],
                extensions: ["lottie"]
            )
        ))
    }
}
