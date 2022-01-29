import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ManifestLoaderErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            ManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).description,
            "Couldn't find ProjectDescription.framework at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).description,
            "Unexpected output trying to parse the manifest at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).description,
            "Project.swift not found at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestNotFound(nil, AbsolutePath("/test/")).description,
            "Manifest not found at path /test"
        )
        XCTAssertEqual(
            ManifestLoaderError.manifestLoadingFailed(path: AbsolutePath("/test/"), context: "Context").description,
            """
            Unable to load manifest at \("/test".bold())
            Context
            """
        )
    }

    func test_type() {
        XCTAssertEqual(ManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).type, .bug)
        XCTAssertEqual(ManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).type, .bug)
        XCTAssertEqual(ManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).type, .abort)
        XCTAssertEqual(ManifestLoaderError.manifestLoadingFailed(path: AbsolutePath("/test/"), context: "Context").type, .abort)
    }
}
