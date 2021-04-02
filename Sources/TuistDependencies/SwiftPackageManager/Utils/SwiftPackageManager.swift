import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// Protocol that defines an interface to interact with the Swift Package Manager.
public protocol SwiftPackageManaging {
    /// Resolves package dependencies.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func resolve(at path: AbsolutePath) throws

    /// Generates an Xcode project for a `Package.swift` manifest file.
    /// - Parameters:
    ///   - path: Directory where the `Package.swift` is defined.
    ///   - outputPath: Path where the Xcode project should be generated
    func generateXcodeProject(at path: AbsolutePath, outputPath: AbsolutePath) throws

    /// Loads a `Package.swift` manifest file info.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo

    /// Loads the resolved dependency graph.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func loadDependencies(at path: AbsolutePath) throws -> PackageDependency
}

public final class SwiftPackageManager: SwiftPackageManaging {
    public init() {}

    public func resolve(at path: AbsolutePath) throws {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["resolve"])

        try System.shared.run(command)
    }

    public func generateXcodeProject(at path: AbsolutePath, outputPath: AbsolutePath) throws {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["generate-xcodeproj", "--output", outputPath.pathString])

        try System.shared.run(command)
    }

    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["dump-package"])

        let json = try System.shared.capture(command)

        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        return try decoder.decode(PackageInfo.self, from: data)
    }

    public func loadDependencies(at path: AbsolutePath) throws -> PackageDependency {
        let command = buildSwiftPackageCommand(packagePath: path, subcommand: ["show-dependencies", "--format", "json"])

        let json = try System.shared.capture(command)

        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        return try decoder.decode(PackageDependency.self, from: data)
    }

    // MARK: - Helpers

    private func buildSwiftPackageCommand(packagePath: AbsolutePath, subcommand: [String]) -> [String] {
        [
            "swift",
            "package",
            "--package-path",
            packagePath.pathString,
        ]
            +
            subcommand
    }
}
