import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

class GeneratorPathsErrorTests: TuistUnitTestCase {
    func test_type_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = GeneratorPathsError.rootDirectoryNotFound(path)

        // Then
        XCTAssertEqual(error.type, .abort)
    }

    func test_description_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = GeneratorPathsError.rootDirectoryNotFound(path)

        // Then
        XCTAssertEqual(
            error.description,
            "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory."
        )
    }
}

class GeneratorPathsTests: TuistUnitTestCase {
    var subject: GeneratorPaths!
    var path: AbsolutePath!
    var rootDirectoryLocator: MockRootDirectoryLocator!

    override func setUp() {
        super.setUp()
        path = try! temporaryPath()
        rootDirectoryLocator = MockRootDirectoryLocator()
        rootDirectoryLocator.locateStub = path.appending(component: "Root")
        subject = GeneratorPaths(
            manifestDirectory: path,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    override func tearDown() {
        subject = nil
        rootDirectoryLocator = nil
        path = nil
        super.tearDown()
    }

    func test_resolve_when_relative_to_current_file() throws {
        // Given
        let filePath = Path(
            "file.swift",
            type: .relativeToCurrentFile,
            callerPath: path.pathString
        )

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        XCTAssertEqual(got, path.removingLastComponent().appending(component: "file.swift"))
    }

    func test_resolve_when_relative_to_manifest() throws {
        // Given
        let filePath = Path.relativeToManifest("file.swift")

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        XCTAssertEqual(got, path.appending(component: "file.swift"))
    }

    func test_resolve_when_relative_to_root_directory() throws {
        // Given
        let filePath = Path.relativeToRoot("file.swift")

        // When
        let got = try subject.resolve(path: filePath)

        // Then
        XCTAssertEqual(got, path.appending(component: "Root").appending(component: "file.swift"))
    }

    func test_resolve_throws_when_the_root_directory_cant_be_found() throws {
        // Given
        let filePath = Path.relativeToRoot("file.swift")
        rootDirectoryLocator.locateStub = nil

        // When
        XCTAssertThrowsSpecific(try subject.resolve(path: filePath), GeneratorPathsError.rootDirectoryNotFound(path))
    }
}
