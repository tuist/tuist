import Basic
import Foundation
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class DerivedFileGeneratorTests: TuistUnitTestCase {
    var infoPlistContentProvider: MockInfoPlistContentProvider!
    var subject: DerivedFileGenerator!

    override func setUp() {
        super.setUp()
        infoPlistContentProvider = MockInfoPlistContentProvider()
        subject = DerivedFileGenerator(infoPlistContentProvider: infoPlistContentProvider)
    }

    override func tearDown() {
        infoPlistContentProvider = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_generatesTheInfoPlistFiles_whenDictionaryInfoPlist() throws {
        // Given
        let sourceRootPath = fileHandler.currentPath
        let target = Target.test(name: "Target", infoPlist: InfoPlist.dictionary(["a": "b"]))
        let project = Project.test(name: "App", targets: [target])
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        let path = infoPlistsPath.appending(component: "Target.plist")

        // When
        _ = try subject.generate(project: project,
                                 sourceRootPath: sourceRootPath)

        // Then
        XCTAssertTrue(fileHandler.exists(path))
        let writtenData = try Data(contentsOf: path.url)
        let content = try PropertyListSerialization.propertyList(from: writtenData, options: [], format: nil)
        XCTAssertTrue(NSDictionary(dictionary: (content as? [String: Any]) ?? [:])
            .isEqual(to: ["a": "b"]))
    }

    func test_generate_generatesTheInfoPlistFiles_whenExtendingDefault() throws {
        // Given
        let sourceRootPath = fileHandler.currentPath
        let target = Target.test(name: "Target", infoPlist: InfoPlist.extendingDefault(with: ["a": "b"]))
        let project = Project.test(name: "App", targets: [target])
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        let path = infoPlistsPath.appending(component: "Target.plist")
        infoPlistContentProvider.contentStub = ["test": "value"]

        // When
        _ = try subject.generate(project: project,
                                 sourceRootPath: sourceRootPath)

        // Then
        XCTAssertTrue(fileHandler.exists(path))
        XCTAssertTrue(infoPlistContentProvider.contentArgs.first?.target == target)
        XCTAssertTrue(infoPlistContentProvider.contentArgs.first?.extendedWith["a"] == "b")

        let writtenData = try Data(contentsOf: path.url)
        let content = try PropertyListSerialization.propertyList(from: writtenData, options: [], format: nil)
        XCTAssertTrue(NSDictionary(dictionary: (content as? [String: Any]) ?? [:])
            .isEqual(to: ["test": "value"]))
    }

    func test_generate_returnsABlockToDeleteUnnecessaryInfoPlistFiles() throws {
        // Given
        let sourceRootPath = fileHandler.currentPath
        let target = Target.test(infoPlist: InfoPlist.dictionary(["a": "b"]))
        let project = Project.test(name: "App", targets: [target])

        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        try fileHandler.createFolder(infoPlistsPath)
        let oldPlistPath = infoPlistsPath.appending(component: "Old.plist")
        try fileHandler.touch(oldPlistPath)

        // When
        let deleteOldDerivedFiles = try subject.generate(project: project,
                                                         sourceRootPath: sourceRootPath)
        try deleteOldDerivedFiles()

        // Then
        XCTAssertFalse(fileHandler.exists(oldPlistPath))
    }

    func test_generate_checkFolderNotCreated_whenNoGeneratedInfoPlist() throws {
        // Given
        let sourceRootPath = fileHandler.currentPath
        let target = Target.test(name: "Target", infoPlist: .file(path: "/Info.plist"))
        let project = Project.test(name: "App", targets: [target])
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        let path = infoPlistsPath.appending(component: "Target.plist")

        // When
        _ = try subject.generate(project: project,
                                 sourceRootPath: sourceRootPath)

        // Then
        XCTAssertFalse(fileHandler.exists(path))
        XCTAssertFalse(fileHandler.exists(infoPlistsPath))
    }
}
