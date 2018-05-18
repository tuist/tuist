import Foundation
@testable import ProjectDescription
import XCTest

final class SettingsTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        let subject = Settings(base: ["base": "base"],
                               debug: Configuration(settings: ["debug": "debug"],
                                                    xcconfig: "/path/debug.xcconfig"),
                               release: Configuration(settings: ["release": "release"],
                                                      xcconfig: "/path/release"))
        let json = subject.toJSON()
        let expected = """
        {"base": {"base": "base"}, "debug": {"settings": {"debug": "debug"}, "xcconfig": "/path/debug.xcconfig"}, "release": {"settings": {"release": "release"}, "xcconfig": "/path/release"}}
        """
        XCTAssertEqual(json.toString(), expected)
    }
}
