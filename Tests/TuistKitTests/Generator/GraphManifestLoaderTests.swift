import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class GraphManifestLoaderErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).description, "Couldn't find ProjectDescription.framework at path /test")
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).description, "Unexpected output trying to parse the manifest at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).description, "Project.swift not found at path /test")
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(nil, AbsolutePath("/test/")).description, "Manifest not found at path /test")
    }

    func test_type() {
        XCTAssertEqual(GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/")).type, .bug)
        XCTAssertEqual(GraphManifestLoaderError.manifestNotFound(.project, AbsolutePath("/test/")).type, .abort)
    }
}
