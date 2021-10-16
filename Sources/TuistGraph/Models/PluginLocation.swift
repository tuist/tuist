import Foundation

/// The location to a directory containing a `Plugin` manifest.
public enum PluginLocation: Hashable, Equatable {
    public enum GitID: Hashable, Equatable {
        case sha(String)
        case tag(String)
    }
    
    /// An absolute path `String` to a directory a `Plugin` manifest.
    ///
    /// Example:
    /// ```
    /// .local(path: "/User/local/bin")
    /// ```
    case local(path: String)

    /// A `URL` to a `git` repository pointing at a `GitID` - either sha or tag.
    ///
    /// Examples:
    /// ```
    /// .git(url: "https://git/helpers.git", gitID: .tag("1.0.0"))
    /// .git(url: "https://git/helpers.git", gitID: .sha("1.0.0"))
    /// ```
    case git(url: String, gitID: GitID)
}

// MARK: - description

extension PluginLocation: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .local(path):
            return "local path: \(path)"
        case let .git(url, .tag(tag)):
            return "git url: \(url), tag: \(tag)"
        case let .git(url, .sha(sha)):
            return "git url: \(url), sha: \(sha)"
        }
    }
}
