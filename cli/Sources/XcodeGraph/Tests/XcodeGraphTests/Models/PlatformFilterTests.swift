import Foundation
import Testing
@testable import XcodeGraph

struct PlatformFilterTests {
    @Test func test_xcodeprojValue() {
        #expect(PlatformFilter.catalyst.xcodeprojValue == "maccatalyst")
        #expect(PlatformFilter.ios.xcodeprojValue == "ios")
        #expect(PlatformFilter.driverkit.xcodeprojValue == "driverkit")
        #expect(PlatformFilter.macos.xcodeprojValue == "macos")
        #expect(PlatformFilter.tvos.xcodeprojValue == "tvos")
        #expect(PlatformFilter.watchos.xcodeprojValue == "watchos")
    }

    @Test func platformfilters_xcodeprojValue() {
        func xcodeProjValueFor(_ filters: PlatformFilters) -> [String] {
            filters.xcodeprojValue
        }

        #expect(xcodeProjValueFor([.ios, .macos]) == ["ios", "macos"])
        #expect(xcodeProjValueFor([.macos, .ios]) == ["ios", "macos"])
        #expect(xcodeProjValueFor([.tvos, .macos, .ios]) == ["ios", "macos", "tvos"])
    }
}
