import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// Protocol that defines an interface to interact with the Swift Package Manager.
public protocol SwiftPackageManagerControlling {
    /// Resolves package dependencies.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func resolve(at path: AbsolutePath) throws

    /// Updates package dependencies.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func update(at path: AbsolutePath) throws

    /// Sets tools version of package to the given value.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Parameter version: Version of tools. When `nil` then the environment’s version will be set.
    func setToolsVersion(at path: AbsolutePath, to version: String?) throws
}

public final class SwiftPackageManagerController: SwiftPackageManagerControlling {
    public init() {}

    public func resolve(at path: AbsolutePath) throws {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["resolve"])

        try System.shared.run(command)
    }

    public func update(at path: AbsolutePath) throws {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["update"])

        try System.shared.run(command)
    }

    public func setToolsVersion(at path: AbsolutePath, to version: String?) throws {
        let subcommand: [String]
        if let version = version {
            subcommand = ["tools-version", "--set", version]
        } else {
            subcommand = ["tools-version", "--set-current"]
        }

        let command = buildSwiftPackageCommand(packagePath: path, subcommand: subcommand)

        try System.shared.run(command)
    }

    // MARK: - Helpers

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, subcommand: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            + subcommand
    }
}
