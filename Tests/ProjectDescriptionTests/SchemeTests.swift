import Foundation
import XCTest
@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    func test_toJSON() {
        let buildAction = [ExecutionAction(title: "Run Script", scriptText: "echo build_action", target: "target")]
        let testAction = [ExecutionAction(title: "Run Script", scriptText: "echo test_action", target: "target")]
        
        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: ["target"],
                                                      preActions: buildAction,
                                                      postActions: buildAction),
                             testAction: TestAction(targets: ["target"],
                                                    arguments: Arguments(environment: ["test": "b"],
                                                                         launch: ["test": true]),
                                                    config: .debug,
                                                    coverage: true,
                                                    preActions: testAction,
                                                    postActions: testAction),
                             runAction: RunAction(config: .debug,
                                                  executable: "executable",
                                                  arguments: Arguments(environment: ["run": "b"],
                                                                       launch: ["run": true])))

        let expected = "{\"build_action\": {\"targets\": [\"target\"], \"pre_actions\": [{\"title\": \"Run Script\", \"script_text\": \"echo build_action\", \"target\": \"target\"}], \"post_actions\": [{\"title\": \"Run Script\", \"script_text\": \"echo build_action\", \"target\": \"target\"}]}, \"name\": \"scheme\", \"run_action\": {\"arguments\": {\"environment\": {\"run\": \"b\"}, \"launch\": {\"run\": true}}, \"config\": \"debug\", \"executable\": \"executable\"}, \"shared\": true, \"test_action\": {\"arguments\": {\"environment\": {\"test\": \"b\"}, \"launch\": {\"test\": true}}, \"config\": \"debug\", \"coverage\": true, \"targets\": [\"target\"],  \"pre_actions\": [{\"title\": \"Run Script\", \"script_text\": \"echo test_action\", \"target\": \"target\"}], \"post_actions\": [{\"title\": \"Run Script\", \"script_text\": \"echo test_action\", \"target\": \"target\"}]}}"
        assertCodableEqualToJson(subject, expected)
    }
}
