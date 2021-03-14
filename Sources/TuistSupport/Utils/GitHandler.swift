import Foundation
import TSCBasic

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

    private func run(command: String...) throws {
        if Environment.shared.isVerbose {
            try system.runAndPrint(command, verbose: true, environment: System.shared.env)
        } else {
            try system.run(command)
        }
    }
}
