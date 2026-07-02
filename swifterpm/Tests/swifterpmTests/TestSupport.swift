import FileSystem
import Foundation
import Path
@testable import SwifterPMCore

func makeTemporaryDirectory() async throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("swifterpm-tests-\(UUID().uuidString)", isDirectory: true)
    try await fileSystem.makeDirectory(
        at: directory.absolutePath, options: [.createTargetParentDirectories])
    return directory
}

func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = try await makeTemporaryDirectory()
    do {
        let result = try await body(directory)
        try? await fileSystem.remove(directory.absolutePath)
        return result
    } catch {
        try? await fileSystem.remove(directory.absolutePath)
        throw error
    }
}

func writeCachedManifest(_ manifest: [String: Any], packageDir: URL) async throws {
    try await fileSystem.makeDirectory(
        at: packageDir.absolutePath, options: [.createTargetParentDirectories])
    try await writeMinimalPackageManifest(at: packageDir, name: "Fixture")
    try await fileSystem.atomicWrite(
        JSONFormatter.prettyData(manifest),
        to: ManifestLoader.cacheFilePath(packageDir: packageDir)
    )
}

func writeMinimalPackageManifest(at packageDir: URL, name: String) async throws {
    try await fileSystem.makeDirectory(
        at: packageDir.absolutePath, options: [.createTargetParentDirectories])
    try await fileSystem.atomicWrite(
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(name: "\(name)")
        """,
        to: packageDir.appendingPathComponent("Package.swift")
    )
}

func fixtureURL(_ components: String...) async throws -> URL {
    try await fixtureURL(components)
}

func fixtureURL(_ components: [String]) async throws -> URL {
    let relative = ["Tests", "swifterpmTests", "Fixtures"] + components
    let env = ProcessInfo.processInfo.environment
    var candidates = try [
        URL(fileURLWithPath: await fileSystem.currentWorkingDirectory().pathString)
            .appendingPathComponents(relative),
    ]

    if let testSrcDir = env["TEST_SRCDIR"] {
        let srcDir = URL(fileURLWithPath: testSrcDir)
        if let workspace = env["TEST_WORKSPACE"] {
            candidates.append(
                srcDir.appendingPathComponent(workspace).appendingPathComponents(relative))
        }
        candidates.append(srcDir.appendingPathComponents(relative))
        candidates.append(srcDir.appendingPathComponent("_main").appendingPathComponents(relative))
    }

    for candidate in candidates where try (await fileSystem.exists(candidate.absolutePath)) {
        return candidate
    }
    throw ToolError.message("fixture not found: \(components.joined(separator: "/"))")
}

func emptyManifest(name: String = "Fixture") -> [String: Any] {
    [
        "name": name,
        "dependencies": [],
        "products": [],
        "targets": [],
    ]
}

func installedSwiftSupportsManifest(at packageDir: URL) async throws -> Bool {
    guard let required = try await manifestToolsVersion(at: packageDir) else {
        return true
    }
    return try await installedSwiftVersion() >= required
}

private func manifestToolsVersion(at packageDir: URL) async throws -> SwiftToolchainVersion? {
    let manifest = packageDir.appendingPathComponent("Package.swift")
    let contents = try String(data: await fileSystem.readFile(at: manifest.absolutePath), encoding: .utf8)
        ?? ""
    guard let firstLine = contents.split(separator: "\n", omittingEmptySubsequences: false).first,
          let range = firstLine.range(of: "swift-tools-version:")
    else {
        return nil
    }
    return SwiftToolchainVersion(
        String(
            firstLine[range.upperBound...]
                .drop(while: { $0.isWhitespace })
                .prefix(while: { $0.isNumber || $0 == "." })
        ))
}

private func installedSwiftVersion() async throws -> SwiftToolchainVersion {
    let output = try await SystemProcess.output("/usr/bin/swift", ["--version"])
    for marker in ["Apple Swift version ", "Swift version "] {
        if let range = output.range(of: marker),
           let version = SwiftToolchainVersion(
               String(
                   output[range.upperBound...]
                       .prefix(while: { $0.isNumber || $0 == "." })
               ))
        {
            return version
        }
    }
    throw ToolError.message("could not determine installed Swift version from: \(output)")
}

private struct SwiftToolchainVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let components = string.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }
        major = components[0]
        minor = components[1]
        patch = components.count > 2 ? components[2] : 0
    }

    static func < (lhs: SwiftToolchainVersion, rhs: SwiftToolchainVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
