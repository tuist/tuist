import Foundation
import ProjectDescription
import TuistGraph
import TuistSupport

import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class PackageInfoGraphPlatformTests: TuistUnitTestCase {
    func test_platformNameCorrectCase() throws {
        let iosPlatform = PackageInfo.Platform(platformName: "iOS", version: "17.0.0", options: [])

        let graphPlatform = try iosPlatform.graphPlatform()
        let destinations = try iosPlatform.destinations()

        XCTAssertEqual(graphPlatform, .iOS)
        XCTAssertEqual(destinations, [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign])
    }

    func test_platformNameLowerCase() throws {
        let iosPlatform = PackageInfo.Platform(platformName: "ios", version: "17.0.0", options: [])

        let graphPlatform = try iosPlatform.graphPlatform()
        let destinations = try iosPlatform.destinations()

        XCTAssertEqual(graphPlatform, .iOS)
        XCTAssertEqual(destinations, [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign])
    }

    func test_platformNameMixedCase() throws {
        let iosPlatform = PackageInfo.Platform(platformName: "VisiOnOS", version: "17.0.0", options: [])

        let graphPlatform = try iosPlatform.graphPlatform()
        let destinations = try iosPlatform.destinations()

        XCTAssertEqual(graphPlatform, .visionOS)
        XCTAssertEqual(destinations, [.appleVision])
    }
}
