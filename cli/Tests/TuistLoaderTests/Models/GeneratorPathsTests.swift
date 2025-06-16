import Mockable
import Path
import TuistCore
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

final class GeneratorPathsTests: TuistUnitTestCase {
    private var path: AbsolutePath!
    private var subject: GeneratorPaths!

    override func setUp() {
        super.setUp()
        path = try! temporaryPath()
        subject = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: path.appending(component: "Root")
        )
    }

    override func tearDown() {
        path = nil
        subject = nil
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
}
