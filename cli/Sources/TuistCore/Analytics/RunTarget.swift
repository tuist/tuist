import XcodeGraph

/// A simplified version of `Target` to store in `CommandEvent`.
public struct RunTarget: Codable, Hashable {
    public let name: String
    public let binaryCacheMetadata: RunCacheTargetMetadata?
    public let selectiveTestingMetadata: RunCacheTargetMetadata?

    public init(
        name: String,
        binaryCacheMetadata: RunCacheTargetMetadata?,
        selectiveTestingMetadata: RunCacheTargetMetadata?
    ) {
        self.name = name
        self.binaryCacheMetadata = binaryCacheMetadata
        self.selectiveTestingMetadata = selectiveTestingMetadata
    }
}

#if DEBUG
    extension RunTarget {
        public static func test(
            name: String = "Target",
            binaryCacheMetadata: RunCacheTargetMetadata? = nil,
            selectiveTestingMetdata: RunCacheTargetMetadata? = nil
        ) -> Self {
            Self(
                name: name,
                binaryCacheMetadata: binaryCacheMetadata,
                selectiveTestingMetadata: selectiveTestingMetdata
            )
        }
    }
#endif
