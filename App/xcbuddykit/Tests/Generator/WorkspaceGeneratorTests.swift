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
}
