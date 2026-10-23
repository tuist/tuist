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

func writeCachedManifest(
    _ manifest: [String: Any], packageDir: URL, cacheFile: URL? = nil, disableSandbox: Bool = false
) async throws {
    try await fileSystem.makeDirectory(
        at: packageDir.absolutePath, options: [.createTargetParentDirectories])
    try await writeMinimalPackageManifest(at: packageDir, name: "Fixture")
    let cachePath = cacheFile ?? ManifestLoader.cacheFilePath(packageDir: packageDir)
    try await ManifestCache.write(
        JSONFormatter.prettyData(manifest), at: cachePath,
        inputs: ManifestCache.inputs(packageDir: packageDir, disableSandbox: disableSandbox)
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

/// Writes a `mirrors.json` in the format `swift package config set-mirror` produces.
func writeMirrorsConfiguration(_ mirrors: [String: String], to path: URL) async throws {
    let object = mirrors.map { ["original": $0.key, "mirror": $0.value] }
    let data = try JSONSerialization.data(withJSONObject: ["object": object, "version": 1])
    try await fileSystem.makeDirectory(
        at: path.deletingLastPathComponent().absolutePath, options: [.createTargetParentDirectories]
    )
    try await fileSystem.atomicWrite(data, to: path)
}

/// Writes a `workspace-state.json` that only records `prebuilts`, as a previous native resolution would, and
/// creates the directories they were extracted to.
func writeWorkspaceState(prebuilts: [[String: Any]], scratchDir: URL) async throws {
    try await fileSystem.makeDirectory(at: scratchDir.absolutePath, options: [.createTargetParentDirectories])
    for case let path as String in prebuilts.map({ $0["path"] }) {
        try await fileSystem.makeDirectory(
            at: URL(fileURLWithPath: path).absolutePath, options: [.createTargetParentDirectories]
        )
    }
    try await fileSystem.atomicWrite(
        JSONFormatter.prettyData([
            "object": ["artifacts": [], "dependencies": [], "prebuilts": prebuilts],
            "version": 7,
        ]),
        to: scratchDir.appendingPathComponent("workspace-state.json")
    )
}

func recordedPrebuiltPaths(scratchDir: URL) async throws -> [String?] {
    let data = try await fileSystem.readFile(at: scratchDir.appendingPathComponent("workspace-state.json").absolutePath)
    let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let object = state?["object"] as? [String: Any]
    return (object?["prebuilts"] as? [[String: Any]] ?? []).map { $0["path"] as? String }
}

/// A swift-syntax prebuilt entry laid out the way SwiftPM extracts it, for a prebuilt `name` of
/// `<compiler tag>-<platform>`.
func swiftSyntaxPrebuilt(scratchDir: URL, version: String, name: String) -> [String: Any] {
    [
        "identity": "swift-syntax",
        "version": version,
        "libraryName": "MacroSupport",
        "path": scratchDir.appendingPathComponent("prebuilts/swift-syntax/\(version)/\(name)-MacroSupport").path,
        "checkoutPath": scratchDir.appendingPathComponent("checkouts/swift-syntax").path,
        "products": ["SwiftSyntax"],
        "includePath": ["Sources/_SwiftSyntaxCShims/include"],
        "cModules": [],
    ]
}

func swiftSyntaxPin(version: String) -> ResolvedPin {
    ResolvedPin(
        identity: "swift-syntax",
        kind: "remoteSourceControl",
        location: "https://github.com/swiftlang/swift-syntax.git",
        state: ResolvedState(branch: nil, revision: "abcdef1234567890", version: version)
    )
}
