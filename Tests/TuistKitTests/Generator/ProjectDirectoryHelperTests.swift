import Basic
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class ProjectDirectoryHelperTests: XCTestCase {
    var subject: ProjectDirectoryHelper!
    var fileHandler: MockFileHandler!
    var environmentController: MockEnvironmentController!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        environmentController = try! MockEnvironmentController()
        subject = ProjectDirectoryHelper(environmentController: environmentController,
                                         fileHandler: fileHandler)
    }

    func test_setupDirectory_when_derivedProjects() throws {
        let path = fileHandler.currentPath
        let got = try subject.setupDirectory(name: "MyApp",
                                             path: path,
                                             directory: .derivedProjects)
        let expected = environmentController.derivedProjectsDirectory.appending(component: "MyApp-\(path.pathString.md5)")

        XCTAssertEqual(got, expected)
        XCTAssertTrue(fileHandler.exists(expected))
    }

    func test_setupDirectory_when_manifest() throws {
        let path = fileHandler.currentPath
        let got = try subject.setupDirectory(name: "name",
                                             path: path,
                                             directory: .manifest)
        XCTAssertEqual(got, path)
    }
}
