import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class TargetActionTests: XCTestCase {
    func test_toJSON_whenPath() {
        let subject = TargetAction.post(path: "path", arguments: ["arg"], name: "name")
        XCTAssertCodable(subject)
    }

    func test_toJSON_whenTool() {
        let subject = TargetAction.post(tool: "tool", arguments: ["arg"], name: "name")
        XCTAssertCodable(subject)
    }

    func test_embedded_script() {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetAction.pre(script: script, name: "name")
        XCTAssertNotNil(subject.embeddedScript)
    }

    func test_toJSON_when_embedded() {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetAction.pre(script: script, name: "name")
        XCTAssertCodable(subject)
    }
}
