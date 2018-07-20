import Basic
import Foundation
import Utility
import XCTest
import xpmcore
@testable import xpmcoreTesting
@testable import xpmenvkit

final class InstallerTests: XCTestCase {
    var shell: MockShell!
    var printer: MockPrinter!
    var fileHandler: FileHandler!
    var buildCopier: MockBuildCopier!
    var versionsController: MockVersionsController!
    var subject: Installer!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        shell = MockShell()
        printer = MockPrinter()
        fileHandler = FileHandler()
        buildCopier = MockBuildCopier()
        versionsController = try! MockVersionsController()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        subject = Installer(shell: shell,
                            printer: printer,
                            fileHandler: fileHandler,
                            buildCopier: buildCopier,
                            versionsController: versionsController)
    }

    func test_install_runs_the_right_commands() throws {
        try subject.install(version: "3.2.1", temporaryDirectory: tmpDir)

        XCTAssertEqual(shell.runAndOutputArgs.count, 3)

        // Clone
        let cloneCommand = shell.runAndOutputArgs[0]
        XCTAssertEqual(cloneCommand, [
            "git", "clone", Constants.gitRepositorySSH,
            tmpDir.path.asString,
        ])

        // Checkout
        let checkoutCommand = shell.runAndOutputArgs[1]
        XCTAssertEqual(checkoutCommand, [
            "git",
            "--git-dir", tmpDir.path.appending(component: ".git").asString,
            "checkout", "-b", "build", "3.2.1",
        ])

        // Build
        let buildCommand = shell.runAndOutputArgs[2]
        XCTAssertEqual(buildCommand, [
            "swift", "build",
            "--package-path", tmpDir.path.asString,
            "--configuration", "release",
        ])
    }

    func test_install_creates_a_version_file() throws {
        try subject.install(version: "3.2.1", temporaryDirectory: tmpDir)
        let versionFilePath = versionsController.path
            .appending(component: "3.2.1")
            .appending(component: Constants.versionFileName)

        XCTAssertEqual(try String(contentsOf: versionFilePath.url), "3.2.1")
    }

    func test_install_prints() throws {
        try subject.install(version: "3.2.1", temporaryDirectory: tmpDir)

        XCTAssertEqual(printer.printArgs.count, 2)
        XCTAssertEqual(printer.printArgs.first, "Installing 3.2.1.")
        XCTAssertEqual(printer.printArgs.last, "Version 3.2.1 installed.")
    }
}
