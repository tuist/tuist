import XcodeGraph

/// A simplified version of `Target` to store in `CommandEvent`.
public struct CommandEventTarget: Codable, Hashable {
    public let name: String
    public let binaryCacheMetadata: CommandEventCacheTargetMetadata?
    public let selectiveTestingMetadata: CommandEventCacheTargetMetadata?

    public init(
        name: String,
        binaryCacheMetadata: CommandEventCacheTargetMetadata?,
        selectiveTestingMetadata: CommandEventCacheTargetMetadata?
    ) {
        self.name = name
        self.binaryCacheMetadata = binaryCacheMetadata
        self.selectiveTestingMetadata = selectiveTestingMetadata
    }
}

#if DEBUG
    extension CommandEventTarget {
        public static func test(
            name: String = "Target",
            binaryCacheMetadata: CommandEventCacheTargetMetadata? = nil,
            selectiveTestingMetdata: CommandEventCacheTargetMetadata? = nil
        ) -> Self {
            Self(
                name: name,
                binaryCacheMetadata: binaryCacheMetadata,
                selectiveTestingMetadata: selectiveTestingMetdata
            )
        }
    }
#endif
