import Foundation

/// A location to a plugin, either local or remote.
public struct PluginLocation: Codable, Equatable {
    /// The type of location `local` or `git`.
    public let type: LocationType

    /// A `Path` to a directory containing a `Plugin` manifest.
    ///
    /// Example:
    /// ```
    /// .local(path: "/User/local/bin")
    /// ```
    public static func local(path: Path) -> Self {
        PluginLocation(type: .local(path: path))
    }

    /// A `URL` to a `git` repository pointing at a `tag`.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", tag: "1.0.0")
    /// ```
    public static func git(url: String, tag: String) -> Self {
        PluginLocation(type: .gitWithTag(url: url, tag: tag))
    }

    /// A `URL` to a `git` repository pointing at a commit `sha`.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", sha: "d06b4b3d")
    /// ```
    public static func git(url: String, sha: String) -> Self {
        PluginLocation(type: .gitWithSha(url: url, sha: sha))
    }
}

// MARK: - Codable

extension PluginLocation {
    public enum LocationType: Codable, Equatable {
        case local(path: Path)
        case gitWithTag(url: String, tag: String)
        case gitWithSha(url: String, sha: String)
    }
}
