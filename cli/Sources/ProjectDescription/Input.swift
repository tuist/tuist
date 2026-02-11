/// Describes an input that affects a foreign build dependency's output.
///
/// Inputs serve two purposes:
/// - **Build phase input file list**: file, folder, and glob inputs are passed as input paths to the Xcode
///   build phase so that Xcode can skip re-running the script when inputs haven't changed.
/// - **Content hashing**: all inputs (including scripts) are used to compute a content hash for Tuist's
///   binary caching and selective testing, so that the foreign build step can be skipped when inputs are unchanged.
public enum Input: Codable, Hashable, Sendable {
    /// A single file whose contents affect the build output.
    case file(Path)

    /// A folder whose contents (recursively) affect the build output.
    case folder(Path)

    /// A glob pattern that resolves to files whose contents affect the build output.
    case glob(Path)

    /// A shell script whose stdout produces a cache key component (e.g. `"git rev-parse HEAD"`).
    ///
    /// Script inputs only contribute to the content hash and are not included in the build phase input file list.
    case script(String)
}
