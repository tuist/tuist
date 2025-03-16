import Path
import XcodeGraph

/// A simplified `GraphTarget` to store in `CommandEvent`.
public struct RunProject: Codable, Hashable {
    public let name: String
    public let path: RelativePath
    public let targets: [RunTarget]

    public init(
        name: String,
        path: RelativePath,
        targets: [RunTarget]
    ) {
        self.name = name
        self.path = path
        self.targets = targets
    }
}

#if DEBUG
    extension RunProject {
        public static func test(
            name: String = "Project",
            // swiftlint:disable:next force_try
            path: RelativePath = try! RelativePath(validating: "App"),
            targets: [RunTarget] = []
        ) -> Self {
            Self(
                name: name,
                path: path,
                targets: targets
            )
        }
    }
#endif
