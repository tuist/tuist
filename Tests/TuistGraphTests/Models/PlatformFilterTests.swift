import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class BuildFilePlatformFilterTests: TuistUnitTestCase {
    func test_xcodeprojValue() {
        XCTAssertEqual(PlatformFilter.catalyst.xcodeprojValue, "maccatalyst")
        XCTAssertEqual(PlatformFilter.ios.xcodeprojValue, "ios")
        XCTAssertEqual(PlatformFilter.driverkit.xcodeprojValue, "driverkit")
        XCTAssertEqual(PlatformFilter.macos.xcodeprojValue, "macos")
        XCTAssertEqual(PlatformFilter.tvos.xcodeprojValue, "tvos")
        XCTAssertEqual(PlatformFilter.watchos.xcodeprojValue, "watchos")
    }
    
}
