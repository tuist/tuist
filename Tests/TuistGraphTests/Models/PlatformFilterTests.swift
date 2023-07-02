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
    
    func test_platformfilters_xcodeprojValue() {
        func xcodeProjValueFor(_ filters: PlatformFilters) -> [String] {
            filters.xcodeprojValue
        }

        XCTAssertEqual(xcodeProjValueFor([.ios, .macos]), ["iphoneos", "macos"])
        XCTAssertEqual(xcodeProjValueFor([.macos, .ios]), ["iphoneos", "macos"])
        XCTAssertEqual(xcodeProjValueFor([.tvos, .macos, .ios]), ["iphoneos", "macos", "tvos"])
    }
}
