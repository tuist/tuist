import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpRequiredTests: TuistUnitTestCase {
    func test_with_when_precondition() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "precondition",
            "name": "test name",
            "is_met": JSON.array([JSON.string("is_met")]),
            "advice": "corrective advice",
        ])
        let got = try UpPrecondition.with(dictionary: dictionary, projectPath: temporaryPath) as? UpPrecondition
        XCTAssertEqual(got?.name, "test name")
        XCTAssertEqual(got?.advice, "corrective advice")
        XCTAssertEqual(got?.isMet, ["is_met"])
    }

    func test_with_when_variable_is() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "precondition",
            "name": "Variable is",
            "is_met": JSON.array([JSON.string("is_met")]),
            "advice": "corrective advice",
        ])
        let got = try UpPrecondition.with(dictionary: dictionary, projectPath: temporaryPath) as? UpPrecondition
        XCTAssertEqual(got?.name, "Variable is")
        XCTAssertEqual(got?.advice, "corrective advice")
        XCTAssertEqual(got?.isMet, ["is_met"])
    }

    func test_with_when_variable_exists() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "precondition",
            "name": "Variable exists",
            "is_met": JSON.array([JSON.string("is_met")]),
            "advice": "corrective advice",
        ])
        let got = try UpPrecondition.with(dictionary: dictionary, projectPath: temporaryPath) as? UpPrecondition
        XCTAssertEqual(got?.name, "Variable exists")
        XCTAssertEqual(got?.advice, "corrective advice")
        XCTAssertEqual(got?.isMet, ["is_met"])
    }
}
