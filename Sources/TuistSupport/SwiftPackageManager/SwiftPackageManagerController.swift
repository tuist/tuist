import Foundation
import TSCBasic

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

    /// Loads the information from the package.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo

    /// Builds a release binary containing release binaries compatible with arm64 and x86.
    /// - Parameters:
    ///     - packagePath: Directory where the `Package.swift` is defined.
    ///     - product: Name of the product to be built.
    ///     - buildPath: Directory where the intermediary build products should be saved.
    ///     - outputPath: Directory where the fat binaries should be saved to.
    func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) throws
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

    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["dump-package"])

        let json = try System.shared.capture(command)

        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        return try decoder.decode(PackageInfo.self, from: data)
    }

    public func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) throws {
        let buildCommand: [String] = [
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple",
        ]

        let arm64Target = "arm64-apple-macosx"
        let x64Target = "x86_64-apple-macosx"
        try System.shared.run(
            buildCommand + [
                arm64Target,
            ]
        )
        try System.shared.run(
            buildCommand + [
                x64Target,
            ]
        )

        if !FileHandler.shared.exists(outputPath) {
            try FileHandler.shared.createFolder(outputPath)
        }

        try System.shared.run([
            "lipo", "-create", "-output", outputPath.appending(component: product).pathString,
            buildPath.appending(components: arm64Target, "release", product).pathString,
            buildPath.appending(components: x64Target, "release", product).pathString,
        ])
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
