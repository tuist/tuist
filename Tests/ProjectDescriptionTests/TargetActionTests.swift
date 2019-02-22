import Foundation
import XCTest
@testable import ProjectDescription

final class TargetActionTests: XCTestCase {
    func test_toJSON_whenPath() {
        let subject = TargetAction.post(path: "path", arguments: ["arg"], name: "name")
        let expected = "{ \"path\": \"path\", \"arguments\": [\"arg\"], \"name\": \"name\", \"order\": \"post\" }"
        assertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_whenTool() {
        let subject = TargetAction.post(tool: "tool", arguments: ["arg"], name: "name")
        let expected = "{ \"tool\": \"tool\", \"arguments\": [\"arg\"], \"name\": \"name\", \"order\": \"post\" }"
        assertCodableEqualToJson(subject, expected)
    }
}
