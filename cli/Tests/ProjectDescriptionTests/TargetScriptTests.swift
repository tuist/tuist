import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class TargetScriptTests: XCTestCase {
    func test_toJSON_whenPath() {
        let subject = TargetScript.post(path: "path", arguments: ["arg"], name: "name")
        XCTAssertCodable(subject)
    }

    func test_toJSON_whenTool() {
        let subject = TargetScript.post(tool: "tool", arguments: ["arg"], name: "name")
        XCTAssertCodable(subject)
    }

    func test_embedded_script() {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetScript.pre(script: script, name: "name")
        XCTAssertEqual(subject.script, .embedded(script))
    }

    func test_toJSON_when_embedded() {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetScript.pre(script: script, name: "name")
        XCTAssertCodable(subject)
    }
}
