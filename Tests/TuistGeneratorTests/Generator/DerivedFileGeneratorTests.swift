import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

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
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(name: "Target", infoPlist: InfoPlist.dictionary(["a": "b"]))
        let project = Project.test(name: "App", targets: [target])

        // When
        let (_, sideEffects) = try subject.generate(graph: Graph.test(), project: project, sourceRootPath: temporaryPath)

        // Then
        let file = try XCTUnwrap(sideEffects.files.first)
        let contents = try XCTUnwrap(file.contents)
        let content = try PropertyListSerialization.propertyList(from: contents, options: [], format: nil)
        XCTAssertTrue(NSDictionary(dictionary: (content as? [String: Any]) ?? [:])
            .isEqual(to: ["a": "b"]))
    }

    func test_generate_generatesTheInfoPlistFiles_whenExtendingDefault() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(name: "Target", infoPlist: InfoPlist.extendingDefault(with: ["a": "b"]))
        let project = Project.test(name: "App", targets: [target])
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: temporaryPath)
        let path = infoPlistsPath.appending(component: "Target.plist")
        infoPlistContentProvider.contentStub = ["test": "value"]

        // When
        let (_, sideEffects) = try subject.generate(graph: Graph.test(), project: project, sourceRootPath: temporaryPath)

        // Then
        let file = try XCTUnwrap(sideEffects.files.first)
        XCTAssertEqual(file.path, path)
        XCTAssertTrue(infoPlistContentProvider.contentArgs.first?.target == target)
        XCTAssertTrue(infoPlistContentProvider.contentArgs.first?.extendedWith["a"] == "b")

        let writtenData = try XCTUnwrap(file.contents)
        let content = try PropertyListSerialization.propertyList(from: writtenData, options: [], format: nil)
        XCTAssertTrue(NSDictionary(dictionary: (content as? [String: Any]) ?? [:])
            .isEqual(to: ["test": "value"]))
    }

    func test_generate_returnsABlockToDeleteUnnecessaryInfoPlistFiles() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let target = Target.test(infoPlist: InfoPlist.dictionary(["a": "b"]))
        let project = Project.test(name: "App", targets: [target])

        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: temporaryPath)
        try FileHandler.shared.createFolder(infoPlistsPath)
        let oldPlistPath = infoPlistsPath.appending(component: "Old.plist")
        try FileHandler.shared.touch(oldPlistPath)

        // When
        let (_, sideEffects) = try subject.generate(graph: Graph.test(),
                                                    project: project,
                                                    sourceRootPath: temporaryPath)

        // Then
        let file = try XCTUnwrap(sideEffects.deletions.first)
        XCTAssertEqual(file, oldPlistPath)
    }
}
