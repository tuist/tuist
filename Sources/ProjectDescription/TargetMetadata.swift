public struct TargetMetadata: Codable, Equatable, Sendable {
    public var tags: [String]

    public static var `default`: TargetMetadata {
        .metadata()
    }

    /// Returns a target metadata.
    ///
    /// - Parameters:
    ///   - tags: The list of tags to use. Used to select focused targets when generating the project.
    /// - Returns: Target metadata
    public static func metadata(
        tags: [String] = []
    ) -> TargetMetadata {
        TargetMetadata(
            tags: tags
        )
    }
}
