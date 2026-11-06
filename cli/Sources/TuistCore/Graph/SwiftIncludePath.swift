import Path

/// A directory exposed to a target through `SWIFT_INCLUDE_PATHS`.
public struct SwiftIncludePath: Hashable, Sendable {
    public let path: AbsolutePath

    /// The `sdk=<sdk>*` build setting condition the path applies under, or `nil` for every SDK.
    public let sdkCondition: String?

    public init(path: AbsolutePath, sdkCondition: String? = nil) {
        self.path = path
        self.sdkCondition = sdkCondition
    }
}
