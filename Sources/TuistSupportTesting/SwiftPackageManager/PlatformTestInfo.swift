import Foundation
import TuistGraph

/// Global configuration of which platform versions used during mock generation
// swiftlint:disable identifier_name
public var PLATFORM_TEST_VERSION: [Platform: String] = [
    .iOS: "10.0",
    .macOS: "10.15",
    .watchOS: "8.5",
    .tvOS: "9.0",
]
