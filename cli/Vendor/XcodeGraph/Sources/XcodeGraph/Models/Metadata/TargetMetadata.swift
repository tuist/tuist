/// The metadata associated with a target.
public struct TargetMetadata: Codable, Equatable, Sendable {
    /// Tags set by the user to group targets together.
    /// Some Tuist features can leverage that information for doing things like filtering.
    public var tags: Set<String>

    @available(*, deprecated, renamed: "metadata(tags:)", message: "Use the static 'metadata' initializer instead")
    public init(
        tags: Set<String>
    ) {
        self.tags = tags
    }

    init(tags: Set<String>, isLocal _: Bool) {
        self.tags = tags
    }

    public static func metadata(tags: Set<String> = Set(), isLocal: Bool = true) -> TargetMetadata {
        self.init(tags: tags, isLocal: isLocal)
    }
}

#if DEBUG
    extension TargetMetadata {
        public static func test(
            tags: Set<String> = []
        ) -> TargetMetadata {
            TargetMetadata.metadata(
                tags: tags
            )
        }
    }
#endif
