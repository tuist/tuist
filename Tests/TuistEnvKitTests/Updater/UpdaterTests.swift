import Foundation
@testable import TuistEnvKit
import XCTest

final class UpdaterTests: XCTestCase {
    var githubClient: MockGitHubClient!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: Updater!
}
