/// Describes an input that contributes to the cache key of a foreign build dependency.
public enum CacheInput: Codable, Hashable, Sendable {
    /// A single file whose contents affect the build output.
    case file(Path)

    /// A folder whose contents (recursively) affect the build output.
    case folder(Path)

    /// A glob pattern that resolves to files whose contents affect the build output.
    case glob(Path)

    /// A shell script whose stdout produces a cache key component (e.g. `"git rev-parse HEAD"`).
    case script(String)
}
