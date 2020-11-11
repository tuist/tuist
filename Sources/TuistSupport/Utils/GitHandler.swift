import Foundation
import TSCBasic

public protocol GitHandling {
    /// Clones the given `url` **in** the given `path`.
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, in path: AbsolutePath) throws

    /// Clones the given `url` **to** the given `path`.
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, to path: AbsolutePath) throws

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
    func checkout(id: String, in path: AbsolutePath) throws
}

/// An implementation of `GitHandling`.
public final class GitHandler: GitHandling {
    private let system: Systeming
    private let fileHandler: FileHandling

    public init(
        system: Systeming = System.shared,
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.system = system
        self.fileHandler = fileHandler
    }

    public func clone(url: String, in path: AbsolutePath) throws {
        try system.runAndPrint("git", "-C", path.pathString, "clone", url)
    }

    public func clone(url: String, to path: AbsolutePath) throws {
        try system.runAndPrint("git", "clone", url, path.pathString)
    }

    public func checkout(id: String, in path: AbsolutePath) throws {
        let gitDirectory = path.appending(.init(".git"))

        try system.runAndPrint(
            "git",
            "--git-dir",
            gitDirectory.pathString,
            "--work-tree",
            path.pathString,
            "checkout",
            id
        )
    }
}
