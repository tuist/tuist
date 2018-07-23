import Foundation
import XCTest
@testable import TuistEnvKit

final class UpdaterTests: XCTestCase {
    var githubClient: MockGitHubClient!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var subject: Updater!
}
