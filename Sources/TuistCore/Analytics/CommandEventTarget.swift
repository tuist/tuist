import XcodeGraph

/// A simplified version of `Target` to store in `CommandEvent`.
public struct CommandEventTarget: Codable, Hashable {
    public init(
        name: String
    ) {
        self.name = name
    }

    public init(
        _ target: Target
    ) {
        name = target.name
    }

    public let name: String
}

#if DEBUG
    extension CommandEventTarget {
        public static func test(
            name: String = "Target"
        ) -> Self {
            Self(
                name: name
            )
        }
    }
#endif
