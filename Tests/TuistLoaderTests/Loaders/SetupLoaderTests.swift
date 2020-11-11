import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class SetupLoaderErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(SetupLoaderError.setupNotFound(.root).description, "We couldn't find a Setup.swift traversing up the directory hierarchy from the path /.")
    }

    func test_type() {
        XCTAssertEqual(SetupLoaderError.setupNotFound(.root).type, .abort)
    }
}

final class SetupLoaderTests: TuistUnitTestCase {
    var subject: SetupLoader!
    var upLinter: MockUpLinter!
    var manifestLoader: MockManifestLoader!
    var manifestFilesLocator: MockManifestFilesLocator!

    override func setUp() {
        super.setUp()
        upLinter = MockUpLinter()
        manifestLoader = MockManifestLoader()
        manifestFilesLocator = MockManifestFilesLocator()
        subject = SetupLoader(upLinter: upLinter, manifestLoader: manifestLoader, manifestFilesLocator: manifestFilesLocator)
    }

    override func tearDown() {
        upLinter = nil
        manifestLoader = nil
        manifestFilesLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_meet_when_no_actions() throws {
        // given
        let projectPath = try temporaryPath()
        let setupPath = projectPath.appending(component: Manifest.setup.fileName(projectPath))
        manifestFilesLocator.locateSetupStub = setupPath

        var receivedPaths = [String]()
        manifestLoader.loadSetupStub = { gotPath, _ in
            receivedPaths.append(gotPath.pathString)
            return []
        }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath, plugins: .none))

        XCTAssertEqual(receivedPaths, [projectPath.pathString])
        XCTAssertEqual(upLinter.lintCount, 0)
    }

    func test_meet_when_actions_provided() throws {
        // given
        let projectPath = try temporaryPath()
        manifestFilesLocator.locateSetupStub = projectPath.appending(component: Manifest.setup.fileName(projectPath))

        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _ in true }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _ in false }
        var lintedUps = [Upping]()
        upLinter.lintStub = { up in lintedUps.append(up); return [] }
        manifestLoader.loadSetupStub = { _, _ in [mockUp1, mockUp2] }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath, plugins: .none))

        XCTAssertEqual(mockUp1.meetCallCount, 0)
        XCTAssertEqual(mockUp2.meetCallCount, 1)
        XCTAssertEqual(upLinter.lintCount, 2)
        XCTAssertEqual(lintedUps.count, 2)
        XCTAssertTrue(mockUp1 === lintedUps[0])
        XCTAssertTrue(mockUp2 === lintedUps[1])
        XCTAssertPrinterOutputContains("Configuring 2")
    }

    func test_meet_traverses_up_the_directory_structure() throws {
        // given
        let temporaryPath = try self.temporaryPath()
        let projectPath = temporaryPath.appending(component: "Project")
        manifestFilesLocator.locateSetupStub = temporaryPath.appending(component: Manifest.setup.fileName(projectPath))

        let mockUp1 = MockUp(name: "1")
        mockUp1.isMetStub = { _ in true }
        let mockUp2 = MockUp(name: "2")
        mockUp2.isMetStub = { _ in false }
        var lintedUps = [Upping]()
        upLinter.lintStub = { up in lintedUps.append(up); return [] }
        manifestLoader.loadSetupStub = { _, _ in [mockUp1, mockUp2] }

        // when / then
        XCTAssertNoThrow(try subject.meet(at: projectPath, plugins: .none))

        XCTAssertEqual(mockUp1.meetCallCount, 0)
        XCTAssertEqual(mockUp2.meetCallCount, 1)
        XCTAssertEqual(upLinter.lintCount, 2)
        XCTAssertEqual(lintedUps.count, 2)
        XCTAssertTrue(mockUp1 === lintedUps[0])
        XCTAssertTrue(mockUp2 === lintedUps[1])
        XCTAssertPrinterOutputContains("Configuring 2")
    }

    func test_meet_when_loadSetup_throws() throws {
        // given
        let projectPath = try temporaryPath()
        manifestFilesLocator.locateSetupStub = projectPath.appending(component: Manifest.setup.fileName(projectPath))
        manifestLoader.loadSetupStub = { _, _ in throw ManifestLoaderError.manifestNotFound(.setup, projectPath) }

        // when / then
        XCTAssertThrowsSpecific(try subject.meet(at: projectPath, plugins: .none),
                                ManifestLoaderError.manifestNotFound(.setup, projectPath))
    }
}
