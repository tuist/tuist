import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct InfoPlistTests {
    @Test func toJSON_when_file() throws {
        let subject = InfoPlist.file(path: "path/Info.plist")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func toJSON_when_dictionary() throws {
        let subject = InfoPlist.dictionary([
            "string": "string",
            "number": 1,
            "boolean": true,
            "dictionary": ["a": "b"],
            "array": ["a", "b"],
            "real": 0.8,
        ])
        #expect(try isCodableRoundTripable(subject))
    }
}
