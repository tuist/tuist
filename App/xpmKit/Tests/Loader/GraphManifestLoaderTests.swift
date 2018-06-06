import Basic
import Foundation
import XCTest
@testable import xpmKit

final class GraphManifestLoaderErrorTests: XCTestCase {
    func test_description_when_projectDescriptionNotFound() {
        let error = GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test"))
        XCTAssertEqual(error.description, "Couldn't find ProjectDescription.framework at path /test.")
    }

    func test_description_when_frameworksFolderNotFound() {
        let error = GraphManifestLoaderError.frameworksFolderNotFound
        XCTAssertEqual(error.description, "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework.")
    }

    func test_description_when_unexpectedOutput() {
        let error = GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/"))
        XCTAssertEqual(error.description, "Unexpected output trying to parse the manifest at path /test.")
    }
}
