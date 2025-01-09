import Path
import XcodeGraph

/// A simplified `GraphTarget` to store in `CommandEvent`.
public struct CommandEventProject: Codable, Hashable {
    public init(
        xcodeProjPath: AbsolutePath
    ) {
        self.xcodeProjPath = xcodeProjPath
    }

    public init(
        _ project: Project
    ) {
        xcodeProjPath = project.xcodeProjPath
    }

    public let xcodeProjPath: AbsolutePath
}

#if DEBUG
    extension CommandEventProject {
        public static func test(
            xcodeProjPath: AbsolutePath =
                try! AbsolutePath(validating: "/test/text.xcodeproj") // swiftlint:disable:this force_try
        ) -> Self {
            Self(
                xcodeProjPath: xcodeProjPath
            )
        }
    }
#endif
