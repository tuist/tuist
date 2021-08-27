import Foundation
import TSCBasic
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistEnvKit

final class GitHubVersionControllerTests: TuistUnitTestCase {
    var subject: GitHubVersionController!

    override func setUp() {
        super.setUp()
        subject = GitHubVersionController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_versions() throws {}
}
