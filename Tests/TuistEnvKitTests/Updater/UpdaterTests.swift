import Foundation
import XCTest

@testable import TuistCoreTesting
@testable import TuistEnvKit

final class UpdaterTests: XCTestCase {
    var githubClient: MockGitHubClient!
    var versionsController: MockVersionsController!
    var installer: MockInstaller!
    var printer: MockPrinter!
    var envUpdater: MockEnvUpdater!
    var subject: Updater!

    override func setUp() {
        githubClient = MockGitHubClient()
        versionsController = try! MockVersionsController()
        installer = MockInstaller()
        printer = MockPrinter()
        envUpdater = MockEnvUpdater()
        subject = Updater(githubClient: githubClient,
                          versionsController: versionsController,
                          installer: installer,
                          printer: printer,
                          envUpdater: envUpdater)
    }

    func test_update_when_no_remote_releases() throws {
        githubClient.releasesStub = { [] }
        try subject.update(force: false)
        XCTAssertEqual(printer.printArgs, ["No remote versions found"])
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_force() throws {
        githubClient.releasesStub = { [Release.test(version: "3.2.1")] }
        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }

        try subject.update(force: true)

        XCTAssertEqual(printer.printArgs, ["Forcing the update of version 3.2.1"])
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
        XCTAssertEqual(installArgs.first?.force, true)
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_there_are_no_updates() throws {
        versionsController.semverVersionsStub = ["3.2.1"]
        githubClient.releasesStub = { [Release.test(version: "3.2.1")] }

        try subject.update(force: false)

        XCTAssertEqual(printer.printArgs, ["There are no updates available"])
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_there_are_updates() throws {
        versionsController.semverVersionsStub = ["3.1.1"]
        githubClient.releasesStub = { [Release.test(version: "3.2.1")] }
        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }

        try subject.update(force: false)

        XCTAssertEqual(printer.printArgs, ["Installing new version available 3.2.1"])
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
        XCTAssertEqual(installArgs.first?.force, false)
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }

    func test_update_when_no_local_versions_available() throws {
        versionsController.semverVersionsStub = []
        githubClient.releasesStub = { [Release.test(version: "3.2.1")] }
        var installArgs: [(version: String, force: Bool)] = []
        installer.installStub = { version, force in installArgs.append((version: version, force: force)) }

        try subject.update(force: false)

        XCTAssertEqual(printer.printArgs, ["No local versions available. Installing the latest version 3.2.1"])
        XCTAssertEqual(installArgs.count, 1)
        XCTAssertEqual(installArgs.first?.version, "3.2.1")
        XCTAssertEqual(installArgs.first?.force, false)
        XCTAssertEqual(envUpdater.updateCallCount, 1)
    }
}
