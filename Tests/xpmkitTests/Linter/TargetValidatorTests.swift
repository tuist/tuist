import Foundation
import XCTest
@testable import xpmkit

final class TargetValidatorErrorTests: XCTestCase {
    func test_type() {
        XCTAssertEqual(TargetValidatorError.missingSourceFiles(target: "target").type, .abort)
    }

    func test_description() {
        XCTAssertEqual(TargetValidatorError.missingSourceFiles(target: "target").description, "The target target doesn't contain source files.")
    }
}

final class TargetValidatorTests: XCTestCase {
    var subject: TargetValidator!

    override func setUp() {
        super.setUp()
        subject = TargetValidator()
    }

    func test_validate_throws_when_target_no_source_files() throws {
        let buildPhase = SourcesBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase]
        let target = Target.test(buildPhases: buildPhases)
        XCTAssertThrowsError(try subject.validate(target: target)) {
            XCTAssertEqual($0 as? TargetValidatorError, TargetValidatorError.missingSourceFiles(target: target.name))
        }
    }
}
