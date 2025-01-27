import Path
import XcodeGraph

/// A simplified `GraphTarget` to store in `CommandEvent`.
public struct CommandEventProject: Codable, Hashable {
    public let name: String
    public let targets: [CommandEventTarget]

    public init(
        name: String,
        targets: [CommandEventTarget]
    ) {
        self.name = name
        self.targets = targets
    }
}

#if DEBUG
    extension CommandEventProject {
        public static func test(
            name: String = "Project",
            targets: [CommandEventTarget] = []
        ) -> Self {
            Self(
                name: name,
                targets: targets
            )
        }
    }
#endif
