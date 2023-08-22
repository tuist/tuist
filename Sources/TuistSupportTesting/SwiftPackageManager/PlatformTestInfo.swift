import Foundation
import TuistGraph

/// Global configuration of which platform versions used during mock generation
public var PLATFORM_TEST_VERSION: [Platform: String] = [ // swiftlint:disable:this identifier_name
    .iOS: "11.0",
    .macOS: "10.15",
    .watchOS: "8.5",
    .tvOS: "11.0",
    .visionOS: "1.0",
]
