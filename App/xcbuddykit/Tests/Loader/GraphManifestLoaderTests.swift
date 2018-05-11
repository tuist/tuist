import Basic
import Foundation
@testable import xcbuddykit
import XCTest

fileprivate struct TestError: Error, ErrorStringConvertible {
    let errorDescription: String
}

final class GraphManifestLoaderErrorTests: XCTestCase {
    func test_description_when_projectDescriptionNotFound() {
        let error = GraphManifestLoaderError.projectDescriptionNotFound(AbsolutePath("/test"))
        XCTAssertEqual(error.errorDescription, "Couldn't find ProjectDescription.framework at path /test.")
    }

    func test_description_when_frameworksFolderNotFound() {
        let error = GraphManifestLoaderError.frameworksFolderNotFound
        XCTAssertEqual(error.errorDescription, "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework.")
    }

    func test_description_when_swiftNotFound() {
        let error = GraphManifestLoaderError.swiftNotFound
        XCTAssertEqual(error.errorDescription, "Couldn't find Swift on your environment. Run 'xcode-select -p' to see if the Xcode path is properly setup.")
    }

    func test_description_when_unexpectedOutput() {
        let error = GraphManifestLoaderError.unexpectedOutput(AbsolutePath("/test/"))
        XCTAssertEqual(error.errorDescription, "Unexpected output trying to parse the manifest at path /test.")
    }
}
