import Foundation

public enum PluginLocation: Hashable, Equatable {
    public enum GitReference: Hashable, Equatable {
        case sha(String)
        case tag(String)
    }

    case local(path: String)
    case git(url: String, gitReference: GitReference, directory: String?, releaseUrl: String?)
}

extension PluginLocation: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .local(path):
            return "local path: \(path)"
        case let .git(url, .tag(tag), directory, releaseUrl):
            return "git url: \(url), tag: \(tag), directory: \(directory ?? "nil"), releaseUrl: \(releaseUrl ?? "nil")"
        case let .git(url, .sha(sha), directory, releaseUrl):
            return "git url: \(url), sha: \(sha), directory: \(directory ?? "nil"), releaseUrl: \(releaseUrl ?? "nil")"
        }
    }
}
