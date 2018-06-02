import Basic
import Foundation
import XCTest
@testable import xpmKit

final class FrameworkEmbedderErrorTests: XCTestCase {
    func test_type() {
        XCTAssertEqual(FrameworkEmbedderError.missingFramework.type, .abort)
        XCTAssertEqual(FrameworkEmbedderError.frameworkNotFound(AbsolutePath("/test")).type, .abort)
        XCTAssertEqual(FrameworkEmbedderError.missingEnvironment.type, .abort)
    }

    func test_description() {
        XCTAssertEqual(FrameworkEmbedderError.missingFramework.description,
                       "A framework needs to be specified.")
        XCTAssertEqual(FrameworkEmbedderError.frameworkNotFound(AbsolutePath("/test")).description,
                       "Framework not found at path /test.")
        XCTAssertEqual(FrameworkEmbedderError.missingEnvironment.description,
                       "Running xpm-embed outside Xcode build phases is not allowed.")
    }
}
