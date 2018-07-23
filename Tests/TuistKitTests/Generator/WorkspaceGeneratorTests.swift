import Basic
import Foundation
import XCTest
@testable import TuistKit

final class WorkspaceGeneratorTests: XCTestCase {
    var projectGenerator: MockProjectGenerator!
    var subject: WorkspaceGenerator!

    override func setUp() {
        super.setUp()
        projectGenerator = MockProjectGenerator()
        subject = WorkspaceGenerator(projectGenerator: projectGenerator)
    }
}
