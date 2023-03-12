import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestLoaderErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            ManifestLoaderError.projectDescriptionNotFound(try AbsolutePath(validating: "/test")).description,
            "Couldn't find ProjectDescription.framework at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.unexpectedOutput(try AbsolutePath(validating: "/test/")).description,
            "Unexpected output trying to parse the manifest at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestNotFound(.project, try AbsolutePath(validating: "/test/")).description,
            "Project.swift not found at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestNotFound(nil, try AbsolutePath(validating: "/test/")).description,
            "Manifest not found at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestLoadingFailed(path: try AbsolutePath(validating: "/test/"), context: "Context")
                .description,
            """
            Unable to load manifest at \("/test".bold())
            Context
            """
        )
    }

    func test_type() {
        XCTAssertEqual(ManifestLoaderError.projectDescriptionNotFound(try AbsolutePath(validating: "/test")).type, .bug)
        XCTAssertEqual(ManifestLoaderError.unexpectedOutput(try AbsolutePath(validating: "/test/")).type, .bug)
        XCTAssertEqual(ManifestLoaderError.manifestNotFound(.project, try AbsolutePath(validating: "/test/")).type, .abort)
        XCTAssertEqual(
            ManifestLoaderError.manifestLoadingFailed(path: try AbsolutePath(validating: "/test/"), context: "Context").type,
            .abort
        )
    }
}
