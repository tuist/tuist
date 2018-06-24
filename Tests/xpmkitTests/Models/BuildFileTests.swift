import Basic
import Foundation
import XCTest
@testable import xpmkit

final class BuildFileErrorTests: XCTestCase {
    func test_description_when_invalidBuildFileType() {
        let error = BuildFileError.invalidBuildFileType("invalid_type")
        XCTAssertEqual(error.description, "Invalid build file type: invalid_type")
    }

    func test_type_when_invalidBuildFileType() {
        let error = BuildFileError.invalidBuildFileType("invalid_type")
        XCTAssertEqual(error.type, .bug)
    }
}

final class BaseResourcesBuildFileTests: XCTestCase {
    func test_from_throws_when_invalidType() {
        let json = JSON.dictionary(["type": "invalid".toJSON()])
        let projectPath = AbsolutePath("/test")
        let context = GraphLoaderContext()
        let expectedError = BuildFileError.invalidBuildFileType("invalid")
        XCTAssertThrowsError(try BaseResourcesBuildFile.from(json: json,
                                                             projectPath: projectPath,
                                                             context: context)) {
            XCTAssertEqual($0 as? BuildFileError, expectedError)
        }
    }
}
