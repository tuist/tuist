import Foundation
import Mockable
import Path
import TSCUtility
import TuistSupport

/// Protocol that defines an interface to interact with the Swift Package Manager.
@Mockable
public protocol PackageInfoLoading {
    /// Loads the information from the package.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo
}

public final class PackageInfoLoader: PackageInfoLoading {
    private let system: Systeming
    private let fileHandler: FileHandling

    public init(
        system: Systeming = System.shared,
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.system = system
        self.fileHandler = fileHandler
    }

    public func resolve(at path: AbsolutePath, printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["resolve"])

        printOutput ?
            try system.runAndPrint(command) :
            try system.run(command)
    }

    public func update(at path: AbsolutePath, printOutput: Bool) throws {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["update"])

        printOutput ?
            try system.runAndPrint(command) :
            try system.run(command)
    }

    public func setToolsVersion(at path: AbsolutePath, to version: Version) throws {
        let extraArguments = ["tools-version", "--set", "\(version.major).\(version.minor)"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        try system.run(command)
    }

    public func getToolsVersion(at path: AbsolutePath) throws -> Version {
        let extraArguments = ["tools-version"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        let rawVersion = try system.capture(command).trimmingCharacters(in: .whitespacesAndNewlines)
        return try Version(versionString: rawVersion)
    }

    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: ["dump-package"])

        let json = try system.capture(command)

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
        try system.run(
            buildCommand + [
                arm64Target,
            ]
        )
        try system.run(
            buildCommand + [
                x64Target,
            ]
        )

        if !fileHandler.exists(outputPath) {
            try fileHandler.createFolder(outputPath)
        }

        try system.run([
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
