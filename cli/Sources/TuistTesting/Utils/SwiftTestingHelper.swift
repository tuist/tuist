import Foundation
import Path
import TuistSupport

public enum SwiftTestingHelper {
    public static func fixturePath(path: RelativePath) -> AbsolutePath {
        // swiftlint:disable:next force_try
        try! AbsolutePath(validating: #file).parentDirectory.parentDirectory.parentDirectory.parentDirectory
            .appending(components: [
                "Tests",
                "Fixtures",
            ])
            .appending(path)
    }
}
