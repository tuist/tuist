import Foundation
import Path

enum SwiftTestingHelper {
    public static func fixturePath(path: RelativePath) -> AbsolutePath {
        // swiftlint:disable:next force_try
        try! AbsolutePath(
            validating: ProcessInfo.processInfo
                .environment["TUIST_CONFIG_SRCROOT"]!
        )
        .appending(components: "Tests", "Fixtures")
        .appending(path)
    }
}
