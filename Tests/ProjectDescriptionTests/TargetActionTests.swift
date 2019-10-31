import Foundation
import TuistCoreTesting
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
}
