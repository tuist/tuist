import Basic
import Foundation
@testable import xcbuddykit
import XCTest

final class ProjectValidationErrorTests: XCTestCase {
    func test_description_whenDuplicatedTargets() {
        let error = ProjectValidationError.duplicatedTargets(["A", "B"], AbsolutePath("/test"))
        XCTAssertEqual(error.errorDescription, "Targets A, B from project at /test have duplicates.")
    }
}

final class ProjectValidatorTests: XCTestCase {
    var subject: ProjectValidator!

    override func setUp() {
        super.setUp()
        subject = ProjectValidator()
    }

    func test_validate_throws_when_there_are_duplicated_targets() throws {
        let target = Target.test(name: "A")
        let project = Project.test(targets: [target, target])
        XCTAssertThrowsError(try subject.validate(project)) { error in
            XCTAssertEqual(error as? ProjectValidationError, ProjectValidationError.duplicatedTargets(["A"], project.path))
        }
    }
}
