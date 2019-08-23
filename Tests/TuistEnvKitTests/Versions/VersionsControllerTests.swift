import Basic
import Foundation
import SPMUtility
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class InstalledVersionTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InstalledVersion.reference("ref").description, "ref")
        XCTAssertEqual(InstalledVersion.semver(Version(string: "3.2.1")!).description, "3.2.1")
    }
}

final class VersionsControllerTests: XCTestCase {
    var environmentController: MockEnvironmentController!
    var fileHandler: MockFileHandler!
    var subject: VersionsController!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        environmentController = try! MockEnvironmentController()
        subject = VersionsController(environmentController: environmentController)
    }

    func test_install() throws {
        try subject.install(version: "3.2.1") { path in
            let testPath = path.appending(component: "test")
            try Data().write(to: testPath.url)
        }

        let versionsPath = environmentController.versionsDirectory
        let testPath = versionsPath.appending(RelativePath("3.2.1/test"))

        XCTAssertTrue(fileHandler.exists(testPath))
    }

    func test_path_for_version() {
        let got = subject.path(version: "ref")

        XCTAssertEqual(got, environmentController.versionsDirectory.appending(component: "ref"))
    }

    func test_versions() throws {
        try fileHandler.createFolder(environmentController.versionsDirectory.appending(component: "3.2.1"))
        try fileHandler.createFolder(environmentController.versionsDirectory.appending(component: "ref"))

        let versions = subject.versions()

        XCTAssertTrue(versions.contains(.reference("ref")))
        XCTAssertTrue(versions.contains(.semver(Version(string: "3.2.1")!)))
    }
}
