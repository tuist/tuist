import Path
import XcodeGraph

/// A simplified `GraphTarget` to store in `CommandEvent`.
public struct CommandEventProject: Codable, Hashable {
    public let name: String
    public let path: RelativePath
    public let targets: [CommandEventTarget]

    public init(
        name: String,
        path: RelativePath,
        targets: [CommandEventTarget]
    ) {
        self.name = name
        self.path = path
        self.targets = targets
    }
}

#if DEBUG
    extension CommandEventProject {
        public static func test(
            name: String = "Project",
            // swiftlint:disable:next force_try
            path: RelativePath = try! RelativePath(validating: "App"),
            targets: [CommandEventTarget] = []
        ) -> Self {
            Self(
                name: name,
                path: path,
                targets: targets
            )
        }
    }
#endif
