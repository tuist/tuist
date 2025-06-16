/// Represents the order in which targets are built within an Xcode scheme.
public enum BuildOrder: Codable, Sendable {
    /// Builds targets automatically based on their dependency graph.
    /// This is the default and recommended setting for most projects.
    case dependency

    /// Builds targets in the order they appear in the scheme’s Build list.
    /// Use this when you need fine-grained control.
    ///
    /// - Warning: This option is deprecated and may not be respected in future versions of Xcode.
    /// Use `dependency` to ensure reliable and maintainable build behavior.
    case manual
}
