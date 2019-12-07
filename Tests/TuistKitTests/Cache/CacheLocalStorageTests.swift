import Foundation
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CacheLocalStorageErrorTests: TuistUnitTestCase {
    func test_type() {
        XCTAssertEqual(CacheLocalStorageError.xcframeworkNotFound(hash: "hash").type, .abort)
    }

    func test_description() {
        XCTAssertEqual(CacheLocalStorageError.xcframeworkNotFound(hash: "hash").description, "File with hash 'hash' not found in the local cache")
    }
}
