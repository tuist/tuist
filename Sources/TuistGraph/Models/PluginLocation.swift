import Foundation

/// The location to a directory containing a `Plugin` manifest.
public enum PluginLocation: Hashable, Equatable {
    /// An absolute path `String` to a directory a `Plugin` manifest.
    ///
    /// Example:
    /// ```
    /// .local(path: "/User/local/bin")
    /// ```
    case local(path: String)

    /// A `URL` to a `git` repository pointing at a `tag`.
    ///
    /// Example:
    /// ```
    /// .gitWithTag(url: "https://git/helpers.git", tag: "1.0.0")
    /// ```
    case gitWithTag(url: String, tag: String)

    /// A `URL` to a `git` repository pointing at a commit `sha`.
    ///
    /// Example:
    /// ```
    /// .gitWithHash(url: "https://git/helpers.git", sha: "d06b4b3d")
    /// ```
    case gitWithSha(url: String, sha: String)
}

// MARK: - description

extension PluginLocation: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .local(path):
            return "local path: \(path)"
        case let .gitWithTag(url, tag):
            return "git url: \(url), tag: \(tag)"
        case let .gitWithSha(url, sha):
            return "git url: \(url), sha: \(sha)"
        }
    }
}
