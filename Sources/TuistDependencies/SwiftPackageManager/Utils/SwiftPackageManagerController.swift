import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// Protocol that defines an interface to interact with the Swift Package Manager.
public protocol SwiftPackageManagerControlling {
    /// Resolves package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - printOutput: When true it prints the Swift Package Manager's ouput.
    func resolve(at path: AbsolutePath, printOutput: Bool) throws

    /// Updates package dependencies.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - printOutput: When true it prints the Swift Package Manager's ouput.
    func update(at path: AbsolutePath, printOutput: Bool) throws

    /// Sets tools version of package to the given value.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Parameter version: Version of tools. When `nil` then the environment’s version will be set.
    func setToolsVersion(at path: AbsolutePath, to version: String?) throws
}

public final class SwiftPackageManagerController: SwiftPackageManagerControlling {
    public init() {}

    public func resolve(at path: AbsolutePath, printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["resolve"])

        printOutput ?
            try System.shared.runAndPrint(command) :
            try System.shared.run(command)
    }

    public func update(at path: AbsolutePath, printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["update"])

        printOutput ?
            try System.shared.runAndPrint(command) :
            try System.shared.run(command)
    }

    public func setToolsVersion(at path: AbsolutePath, to version: String?) throws {
        let extraArguments: [String]
        if let version = version {
            extraArguments = ["tools-version", "--set", version]
        } else {
            extraArguments = ["tools-version", "--set-current"]
        }

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        try System.shared.run(command)
    }

    // MARK: - Helpers

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, extraArguments: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            + extraArguments
    }
}
