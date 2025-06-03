import Foundation
import Path
import TuistSupport

enum SwiftTestingHelper {
    public static func fixturePath(path: RelativePath) -> AbsolutePath {
        // swiftlint:disable:next force_try
        try! AbsolutePath(
            validating: Environment.current
                .variables["TUIST_CONFIG_SRCROOT"]!
        )
        .appending(components: "Tests", "Fixtures")
        .appending(path)
    }
}
