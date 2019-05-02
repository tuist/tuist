import Foundation
import XCTest
@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    func test_toJSON() {
        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: ["target"]),
                             testAction: TestAction(targets: ["target"],
                                                    arguments: Arguments(environment: ["a": "b"],
                                                                         launch: ["a": true]),
                                                    config: .debug,
                                                    coverage: true),
                             runAction: RunAction(config: .debug,
                                                  executable: "executable",
                                                  arguments: Arguments(environment: ["a": "b"],
                                                                       launch: ["a": true])))

        let expected = "{\"build_action\": {\"targets\": [\"target\"], \"pre_actions\": [\"pre_action\"]}, \"name\": \"scheme\", \"run_action\": {\"arguments\": {\"environment\": {\"a\": \"b\"}, \"launch\": {\"a\": true}}, \"config\": \"debug\", \"executable\": \"executable\"}, \"shared\": true, \"test_action\": {\"arguments\": {\"environment\": {\"a\": \"b\"}, \"launch\": {\"a\": true}}, \"config\": \"debug\", \"coverage\": true, \"targets\": [\"target\"]}}"
        assertCodableEqualToJson(subject, expected)
    }
}
