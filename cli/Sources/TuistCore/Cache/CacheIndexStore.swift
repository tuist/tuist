import Foundation

/// Shared constants for shipping Xcode index data alongside binary-cached modules.
///
/// Cache warming compiles each module with `-file-prefix-map` so the emitted index units carry
/// these tokens instead of the warm machine's absolute paths. On the consuming side the tokens are
/// remapped back to the developer's checkout and derived data, which is what lets Open Quickly and
/// find-references resolve symbols for modules consumed as binaries.
public enum CacheIndexStore {
    /// Directory that holds a target's sliced index store inside its cache artifact.
    public static let directoryName = "IndexStore"

    /// Placeholder the warm build's source root is remapped to. The consumer substitutes it with the
    /// local checkout root when importing the index data.
    public static let sourceRootToken = "/__TUIST_SRCROOT__"

    /// Placeholder the warm build's derived data root is remapped to. The consumer substitutes it with
    /// the local derived data root when importing the index data.
    public static let buildRootToken = "/__TUIST_BUILD__"
}
