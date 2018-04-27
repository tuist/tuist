import Basic
import Foundation
@testable import xcbuddykit
import XCTest

final class WorkspaceGeneratorTests: XCTestCase {
    var projectGenerator: MockProjectGenerator!
    var subject: WorkspaceGenerator!

    override func setUp() {
        super.setUp()
        projectGenerator = MockProjectGenerator()
        subject = WorkspaceGenerator(projectGenerator: projectGenerator)
    }

    func test_generate_generates_a_workspace() throws {
        let tmpdir = try TemporaryDirectory(removeTreeOnDeinit: true)
//        try subject.generate(path: tmpdir.path)
    }
}
