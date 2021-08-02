import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class BuildFilePlatformFilterTests: TuistUnitTestCase {
    func test_xcodeprojValue() {
        XCTAssertEqual(BuildFilePlatformFilter.catalyst.xcodeprojValue, "maccatalyst")
        XCTAssertEqual(BuildFilePlatformFilter.ios.xcodeprojValue, "ios")
    }
}
