/// Patterns for matching against a target.
public enum TargetPattern: Hashable {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)

    public static func pattern(_ rawValue: String) -> Self {
        let tagPrefix = "tag:"
        if rawValue.hasPrefix(tagPrefix) {
            return .tagged(String(rawValue.dropFirst(tagPrefix.count)))
        } else {
            return .named(rawValue)
        }
    }
}
