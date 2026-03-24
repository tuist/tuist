import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct TargetScriptTests {
    @Test func toJSON_whenPath() throws {
        let subject = TargetScript.post(path: "path", arguments: ["arg"], name: "name")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func toJSON_whenTool() throws {
        let subject = TargetScript.post(tool: "tool", arguments: ["arg"], name: "name")
        #expect(try isCodableRoundTripable(subject))
    }

    @Test func embedded_script() {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetScript.pre(script: script, name: "name")
        #expect(subject.script == .embedded(script))
    }

    @Test func toJSON_when_embedded() throws {
        let script = """
        echo 'Hello World'
        wd=$(pwd)
        echo "$wd"
        """

        let subject = TargetScript.pre(script: script, name: "name")
        #expect(try isCodableRoundTripable(subject))
    }
}
