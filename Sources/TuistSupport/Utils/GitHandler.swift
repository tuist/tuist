import Foundation
import TSCBasic
import TSCUtility

public protocol GitHandling {
    /// Clones the given `url` **into** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, into path: AbsolutePath) throws

    /// Clones the given `url` **to** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, to path: AbsolutePath?) throws

    /// Checkout to some git `id` in the given `path`.
    ///
    /// The `id` must be something known to the `git checkout` command, which includes:
    ///  - A branch, i.e. `main`.
    ///  - A tag, i.e. `1.0.0`
    ///  - A sha, i.e. `028c13b`
    ///
    /// - Parameters:
    ///   - id: An identifier for the `git checkout` command.
    ///   - path: The path to the git repository (location with `.git` directory) in which to perform the checkout.
    func checkout(id: String, in path: AbsolutePath?) throws

    /// Return the tagged versions of the repository at the given `url`.
    ///
    /// - Parameters:
    ///   - url: The `url` of the git repository.
    func remoteTaggedVersions(url: String) throws -> [Version]
}

/// An implementation of `GitHandling`.
/// Uses the system to execute git commands.
public final class GitHandler: GitHandling {
    private let system: Systeming

    public init(
        system: Systeming = System.shared
    ) {
        self.system = system
    }

    public func clone(url: String, into path: AbsolutePath) throws {
        try run(command: "git", "-C", path.pathString, "clone", url)
    }

    public func clone(url: String, to path: AbsolutePath? = nil) throws {
        if let path = path {
            try run(command: "git", "clone", url, path.pathString)
        } else {
            try run(command: "git", "clone", url)
        }
    }

    public func checkout(id: String, in path: AbsolutePath?) throws {
        if let path = path {
            let gitDirectory = path.appending(component: ".git")
            try run(command: "git", "--git-dir", gitDirectory.pathString, "--work-tree", path.pathString, "checkout", id)
        } else {
            try run(command: "git", "checkout", id)
        }
    }

    public func remoteTaggedVersions(url: String) throws -> [Version] {
        try parseVersions(lsRemote(url: url))
    }

    private func run(command: String...) throws {
        if Environment.shared.isVerbose {
            try system.runAndPrint(command, verbose: true, environment: System.shared.env)
        } else {
            try system.run(command)
        }
    }

    private func capture(command: String...) throws -> String {
        if Environment.shared.isVerbose {
            return try system.capture(command, verbose: true, environment: System.shared.env)
        } else {
            return try system.capture(command)
        }
    }

    private func parseVersions(_ unparsed: String) throws -> [Version] {
        let regex = try NSRegularExpression(pattern: ##"tags/([0-9]+.[0-9]+.[0-9]+)"##, options: [])
        let changelogRange = NSRange(
            unparsed.startIndex ..< unparsed.endIndex,
            in: unparsed
        )
        let matches = regex.matches(in: unparsed, options: [], range: changelogRange)

        let versions = matches.map { result -> Version in
            let matchRange = result.range(at: 1)
            return Version(stringLiteral: String(unparsed[Range(matchRange, in: unparsed)!]))
        }
        return versions
    }

    private func lsRemote(url: String) throws -> String {
        try capture(command: "git", "ls-remote", "-t", "--sort=v:refname", url)
    }
}
