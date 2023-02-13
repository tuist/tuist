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
    /// You can also specify a custom directory in case the plugin is not located at the root of the repository.
    /// You can also specify a custom release URL from where the plugin binary should be downloaded. If not specified,
    /// it defaults to the GitHub release URL. Note that the URL should be publicly reachable.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", tag: "1.0.0", directory: "PluginDirectory")
    /// ```
    public static func git(url: String, tag: String, directory: String? = nil, releaseUrl: String? = nil) -> Self {
        PluginLocation(type: .gitWithTag(url: url, tag: tag, directory: directory, releaseUrl: releaseUrl))
    }

    /// A `URL` to a `git` repository pointing at a commit `sha`.
    /// You can also specify a custom directory in case the plugin is not located at the root of the repository.
    ///
    /// Example:
    /// ```
    /// .git(url: "https://git/plugin.git", sha: "d06b4b3d")
    /// ```
    public static func git(url: String, sha: String, directory: String? = nil) -> Self {
        PluginLocation(type: .gitWithSha(url: url, sha: sha, directory: directory))
    }
}

// MARK: - Codable

extension PluginLocation {
    public enum LocationType: Codable, Equatable {
        case local(path: Path)
        case gitWithTag(url: String, tag: String, directory: String?, releaseUrl: String?)
        case gitWithSha(url: String, sha: String, directory: String?)
    }
}
