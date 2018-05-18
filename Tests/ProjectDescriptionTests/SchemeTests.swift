import Foundation
@testable import ProjectDescription
import XCTest

final class SchemeTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
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
        let json = subject.toJSON()
        let expected = "{\"build_action\": {\"targets\": [\"target\"]}, \"name\": \"scheme\", \"run_action\": {\"arguments\": {\"environment\": {\"a\": \"b\"}, \"launch\": {\"a\": true}}, \"config\": \"debug\", \"executable\": \"executable\"}, \"shared\": true, \"test_action\": {\"arguments\": {\"environment\": {\"a\": \"b\"}, \"launch\": {\"a\": true}}, \"config\": \"debug\", \"coverage\": true, \"targets\": [\"target\"]}}"
        XCTAssertEqual(json.toString(), expected)
    }
}
