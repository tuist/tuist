import Foundation
import XCTest
@testable import ProjectDescription

final class SettingsTests: XCTestCase {
    func test_toJSON() {
        let subject = Settings(base: ["base": "base"],
                               debug: Configuration(settings: ["debug": "debug"],
                                                    xcconfig: "/path/debug.xcconfig"),
                               release: Configuration(settings: ["release": "release"],
                                                      xcconfig: "/path/release"))

        let expected = """
        {"base": {"base": "base"}, "debug": {"settings": {"debug": "debug"}, "xcconfig": "/path/debug.xcconfig"}, "release": {"settings": {"release": "release"}, "xcconfig": "/path/release"}}
        """
        assertCodableEqualToJson(subject, expected)
    }
}
