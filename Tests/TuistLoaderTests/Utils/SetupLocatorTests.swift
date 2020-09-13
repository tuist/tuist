import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

final class SetupLocatorTests: TuistUnitTestCase {
    private var subject: SetupLocator!

    override func setUp() {
        super.setUp()
        subject = SetupLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Setup.swift",
        ])

        // When
        let setupPath = subject.locate(at: try temporaryPath())

        // Then
        XCTAssertNotNil(setupPath)
        XCTAssertEqual(paths.last, setupPath)
    }

    func test_traversing_locate() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
            "Setup.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let setupPath = subject.locate(at: locatingPath)

        // Then
        XCTAssertNotNil(setupPath)
        XCTAssertEqual(paths.last, setupPath)
    }

    func test_locate_where_setup_not_exist() throws {
        // Given
        _ = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])

        // When
        let setupPath = subject.locate(at: try temporaryPath())

        // Then
        XCTAssertNil(setupPath)
    }

    func test_locate_traversing_where_setup_not_exist() throws {
        // Given
        let paths = try createFiles([
            "Module01/File01.swift",
            "Module01/File02.swift",
            "Module01/File03.swift",

            "Module02/File01.swift",
            "Module02/File01.swift",
            "Module02/Subdir01/File01.swift",
            "Module02/Subdir01/File02.swift",

            "File01.swift",
            "File02.swift",
        ])
        let locatingPath = paths[5] // "Module02/Subdir01/File01.swift"

        // When
        let setupPath = subject.locate(at: locatingPath)

        // Then
        XCTAssertNil(setupPath)
    }
}
