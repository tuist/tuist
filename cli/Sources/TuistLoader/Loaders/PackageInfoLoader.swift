import FileSystem
import Foundation
import Mockable
import Path
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

/// Protocol that defines an interface to interact with the Swift Package Manager.
@Mockable
public protocol PackageInfoLoading {
    /// Loads the information from the package.
    /// - Parameter path: Directory where the `Package.swift` is defined.
    /// - Parameter disableSandbox: Whether it should disable the sandbox when dumping the package.
    func loadPackageInfo(at path: AbsolutePath, disableSandbox: Bool) async throws -> PackageInfo
}

public final class PackageInfoLoader: PackageInfoLoading {
    private let system: Systeming
    private let fileSystem: FileSysteming
    private let swiftVersionProvider: SwiftVersionProviding
    private let tuistVersion: String
    private let fileHandler: FileHandling
    private let decoder = JSONDecoder()
    private let cacheDirectory: ThrowableCaching<AbsolutePath>

    private enum CacheConstants {
        static let version = 1
    }

    public init(
        system: Systeming = System.shared,
        fileSystem: FileSysteming = FileSystem(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        swiftVersionProvider: SwiftVersionProviding = SwiftVersionProvider.current,
        tuistVersion: String = Constants.version,
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.system = system
        self.fileSystem = fileSystem
        self.swiftVersionProvider = swiftVersionProvider
        self.tuistVersion = tuistVersion
        self.fileHandler = fileHandler
        cacheDirectory = ThrowableCaching {
            try cacheDirectoriesProvider.cacheDirectory(for: .packageInfo)
        }
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

    public func setToolsVersion(at path: AbsolutePath, to version: TSCUtility.Version) throws {
        let extraArguments = ["tools-version", "--set", "\(version.major).\(version.minor)"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        try system.run(command)
    }

    public func getToolsVersion(at path: AbsolutePath) throws -> TSCUtility.Version {
        let extraArguments = ["tools-version"]

        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        let rawVersion = try system.capture(command).trimmingCharacters(in: .whitespacesAndNewlines)
        return try Version(versionString: rawVersion)
    }

    public func loadPackageInfo(at path: AbsolutePath, disableSandbox: Bool) throws -> PackageInfo {
        if let cached = try loadCachedPackageInfo(at: path, disableSandbox: disableSandbox) {
            return cached
        }

        var extraArguments = ["dump-package"]
        if disableSandbox {
            extraArguments.insert("--disable-sandbox", at: 0)
        }
        let command = buildSwiftPackageCommand(packagePath: path, extraArguments: extraArguments)

        let json = try system.capture(command)

        let data = Data(json.utf8)
        let packageInfo = try decoder.decode(PackageInfo.self, from: data)
        cachePackageInfo(json: json, at: path, disableSandbox: disableSandbox)
        return packageInfo
    }

    public func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) async throws {
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

        if try await !fileSystem.exists(outputPath) {
            try await fileSystem.makeDirectory(at: outputPath)
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

    private func cacheKey(at path: AbsolutePath, disableSandbox: Bool) throws -> String? {
        guard let manifestHash = packageManifestHash(at: path) else { return nil }
        guard let swiftlangVersion = try? swiftVersionProvider.swiftlangVersion() else { return nil }
        let resolvedHash = packageResolvedHash(at: path) ?? "no-resolved"

        let keyComponents = [
            path.pathString,
            manifestHash,
            resolvedHash,
            swiftlangVersion,
            tuistVersion,
            "\(disableSandbox)",
        ]

        return keyComponents.joined(separator: "|").md5
    }

    private func packageManifestHash(at path: AbsolutePath) -> String? {
        guard let contents = try? fileHandler.contentsOfDirectory(path) else { return nil }

        let manifestFiles = contents
            .filter { $0.basename.hasPrefix("Package") && $0.extension == "swift" }
            .sorted { $0.pathString < $1.pathString }

        guard !manifestFiles.isEmpty else { return nil }

        let manifestHashes = manifestFiles.compactMap { file -> String? in
            guard let hash = file.sha256() else { return nil }
            return "\(file.basename):\(hash.base64EncodedString())"
        }

        guard manifestHashes.count == manifestFiles.count else { return nil }

        return manifestHashes.joined(separator: "|").md5
    }

    private func packageResolvedHash(at path: AbsolutePath) -> String? {
        let resolvedCandidates: [AbsolutePath] = [
            path.appending(component: ".package.resolved"),
            path.appending(component: Constants.SwiftPackageManager.packageResolvedName),
            path.appending(components: [".swiftpm", Constants.SwiftPackageManager.packageResolvedName]),
        ]

        var hashes: [String] = []
        for candidate in resolvedCandidates {
            guard FileManager.default.fileExists(atPath: candidate.pathString) else { continue }
            guard let hash = candidate.sha256() else { return nil }
            hashes.append("\(candidate.basename):\(hash.base64EncodedString())")
        }

        guard !hashes.isEmpty else { return nil }
        return hashes.joined(separator: "|").md5
    }

    private func cachedPackageInfoPath(at path: AbsolutePath, disableSandbox: Bool) throws -> AbsolutePath? {
        guard let key = try cacheKey(at: path, disableSandbox: disableSandbox) else { return nil }
        let directory = try cacheDirectory.value
        let fileName = "\(CacheConstants.version).\(key).json"
        return directory.appending(component: fileName)
    }

    private func loadCachedPackageInfo(at path: AbsolutePath, disableSandbox: Bool) throws -> PackageInfo? {
        guard let cachePath = try cachedPackageInfoPath(at: path, disableSandbox: disableSandbox) else { return nil }
        guard FileManager.default.fileExists(atPath: cachePath.pathString) else { return nil }
        guard let cachedData = try? fileHandler.readFile(cachePath) else { return nil }
        return try? decoder.decode(PackageInfo.self, from: cachedData)
    }

    private func cachePackageInfo(json: String, at path: AbsolutePath, disableSandbox: Bool) {
        guard let cachePath = try? cachedPackageInfoPath(at: path, disableSandbox: disableSandbox) else { return }
        do {
            try fileHandler.createFolder(cachePath.removingLastComponent())
        } catch {
            return
        }
        try? fileHandler.write(json, path: cachePath, atomically: true)
    }
}
