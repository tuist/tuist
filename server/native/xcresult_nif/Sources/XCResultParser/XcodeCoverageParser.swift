import FileSystem
import Foundation
import Mockable
import Path

@Mockable
public protocol XcodeCoverageParsing: Sendable {
    /// The absolute paths of the source files the bundle has coverage for, spelled the way the
    /// compiler recorded them, or nil when `xcodebuild` wrote no coverage, which is every run that
    /// did not enable it. Reads the archive's file list alone, so it is cheap next to ``parse``.
    func coveredFilePaths(resultBundlePath: AbsolutePath) async throws -> [String]?

    /// Reads the bundle's coverage report and archive into one entry per source file, tied to
    /// the repository through `manifest`. Returns nil when the bundle carries no coverage data.
    func parse(resultBundlePath: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport?
}

public struct XcodeCoverageParser: XcodeCoverageParsing {
    private let fileSystem: FileSysteming
    private let execute: XCResultToolExecuting

    public init(
        fileSystem: FileSysteming = FileSystem(),
        execute: @escaping XCResultToolExecuting = executeXCResultTool
    ) {
        self.fileSystem = fileSystem
        self.execute = execute
    }

    public func coveredFilePaths(resultBundlePath: AbsolutePath) async throws -> [String]? {
        try await xccov(["view", "--archive", "--file-list"], bundle: resultBundlePath).map { data in
            String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        }
    }

    public func parse(resultBundlePath: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport? {
        // The report carries the target and function hierarchy, the archive the per-line
        // execution counts; neither has what the other does.
        async let reportOutput = xccov(["view", "--report", "--json"], bundle: resultBundlePath)
        async let archiveOutput = xccov(["view", "--archive", "--json"], bundle: resultBundlePath)
        guard let reportData = try await reportOutput, let archiveData = try await archiveOutput else { return nil }

        let report = try JSONDecoder().decode(XccovReport.self, from: reportData)
        let archive = try JSONDecoder().decode([String: [XccovLine]].self, from: archiveData)

        let testTargets = Set(report.targets.filter { Self.isTestBundle($0.buildProductPath) }.map(\.name))
        var targetsByPath: [String: [String]] = [:]
        var functionsByPath: [String: [XcodeCoverageFunction]] = [:]
        var countsByPath: [String: (covered: Int, executable: Int)] = [:]
        for target in report.targets {
            for file in target.files {
                if !(targetsByPath[file.path] ?? []).contains(target.name) {
                    targetsByPath[file.path, default: []].append(target.name)
                }
                // A file linked into several targets is listed under each with the same functions.
                if functionsByPath[file.path] == nil {
                    functionsByPath[file.path] = (file.functions ?? []).map {
                        XcodeCoverageFunction(
                            name: $0.name,
                            lineNumber: $0.lineNumber,
                            executionCount: $0.executionCount,
                            coveredLines: $0.coveredLines,
                            executableLines: $0.executableLines
                        )
                    }
                    countsByPath[file.path] = (file.coveredLines, file.executableLines)
                }
            }
        }

        let roots = Self.roots(manifest.rootDirectories)
        let blobIdsByPath = Dictionary(manifest.files.map { ($0.path, $0.gitBlobId) }, uniquingKeysWith: { first, _ in first })

        // Only the repository's own code counts: third-party packages compiled with instrumentation
        // (checkouts under `.build` or DerivedData) would dominate both the figure and the payload.
        // In a Git checkout the manifest lists the covered files Git does not ignore, which leaves
        // out ignored build and checkout directories too.
        let repositoryPaths = Set(manifest.files.map(\.path))
        let files = Set(archive.keys).union(targetsByPath.keys).compactMap { absolutePath -> XcodeCoverageFile? in
            let path = Self.relativize(absolutePath, to: roots)
            guard !path.hasPrefix("/"), !Self.isDependencyPath(path),
                  repositoryPaths.isEmpty || repositoryPaths.contains(path)
            else { return nil }
            let lines = (archive[absolutePath] ?? []).filter(\.isExecutable).sorted { $0.line < $1.line }
            let counts = lines.map { $0.executionCount ?? 0 }
            let reported = countsByPath[absolutePath]
            let targets = targetsByPath[absolutePath] ?? []
            let productTargets = targets.filter { !testTargets.contains($0) }
            let isTest = !targets.isEmpty && productTargets.isEmpty
            // Test code is left out of every figure, so only its counts travel.
            return XcodeCoverageFile(
                path: path,
                gitBlobId: blobIdsByPath[path],
                targets: productTargets.isEmpty ? targets : productTargets,
                isTest: isTest,
                coveredLines: lines.isEmpty ? reported?.covered ?? 0 : counts.filter { $0 > 0 }.count,
                executableLines: lines.isEmpty ? reported?.executable ?? 0 : lines.count,
                lineNumbers: isTest ? [] : lines.map(\.line),
                executionCounts: isTest ? [] : counts,
                functions: isTest ? [] : functionsByPath[absolutePath] ?? []
            )
        }.sorted { $0.path < $1.path }

        return XcodeCoverageReport(partial: manifest.partial, files: files)
    }

    /// Runs xccov against the bundle and returns what it printed, or nil when the bundle has no
    /// coverage to read, which is the case for every run that did not enable it.
    private func xccov(_ arguments: [String], bundle: AbsolutePath) async throws -> Data? {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage") { temporaryDirectory -> Data? in
            let bundlePath = try await xcresultPath(for: bundle, temporaryDirectory: temporaryDirectory)
            do {
                // Spawned directly rather than through a shell: the bundle path is user-controlled
                // and goes through as one argument, so no quoting is involved.
                let output = try await execute(["/usr/bin/xcrun", "xccov"] + arguments + [bundlePath.pathString])
                if !output.succeeded {
                    if Self.reportsNoCoverage(output.standardError) { return nil }
                    throw XCResultParserError.failedToParseOutput(bundle)
                }
                return Data(output.standardOutput.utf8)
            }
        }
    }

    /// xccov identifies a bundle by its `.xcresult` extension and refuses anything else with
    /// "unrecognized file format". `xcodebuild -resultBundlePath <name>` without an extension
    /// writes `<name>.xcresult` and leaves `<name>` as a symlink to it, so follow the link; a
    /// bundle that really has no extension, which is how the server extracts an upload, is
    /// reached through a temporary link that has one.
    private func xcresultPath(for path: AbsolutePath, temporaryDirectory: AbsolutePath) async throws -> AbsolutePath {
        // A missing bundle is xccov's error to report, not ours to mask.
        guard try await fileSystem.exists(path) else { return path }
        let resolved = try await fileSystem.resolveSymbolicLink(path)
        if resolved.extension == "xcresult" { return resolved }

        let link = temporaryDirectory.appending(component: "bundle.xcresult")
        try await fileSystem.createSymbolicLink(from: link, to: resolved)
        return link
    }

    /// The messages xccov prints for a bundle that has no coverage to read.
    private static func reportsNoCoverage(_ stderr: String) -> Bool {
        stderr.contains("No coverage data") || stderr.contains("No coverage archive present")
    }

    /// Whether the binary belongs to a test bundle. Only the innermost bundle counts: a framework
    /// embedded in a test bundle (`AppTests.xctest/Frameworks/Lib.framework/Lib`) is product code,
    /// while a test bundle inside an app (`App.app/PlugIns/AppTests.xctest/AppTests`) is a test.
    static func isTestBundle(_ buildProductPath: String?) -> Bool {
        let bundleExtensions: Set<String> = ["app", "appex", "bundle", "framework", "xctest"]
        let innermostBundle = (buildProductPath ?? "").split(separator: "/").reversed().first { component in
            bundleExtensions.contains((component as NSString).pathExtension)
        }
        return innermostBundle.map { ($0 as NSString).pathExtension == "xctest" } ?? false
    }

    /// Directories package managers and builds check dependencies out into, for a checkout Git
    /// cannot vouch for.
    static func isDependencyPath(_ path: String) -> Bool {
        let dependencyDirectories: Set<String> = [".build", "DerivedData", "SourcePackages", "Pods", "Carthage"]
        return path.split(separator: "/").contains { dependencyDirectories.contains(String($0)) }
    }

    /// Longest first, so a root nested in another one wins.
    private static func roots(_ rootDirectories: [String]) -> [String] {
        rootDirectories
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .filter { $0.hasPrefix("/") }
            .sorted { $0.count > $1.count }
    }

    /// Plain string prefixes: the manifest already lists every spelling of the root the build
    /// could have used, and whoever processes the bundle may not have the checkout to resolve
    /// anything against.
    private static func relativize(_ path: String, to roots: [String]) -> String {
        for root in roots {
            let prefix = root == "/" ? root : root + "/"
            if path.hasPrefix(prefix), path.count > prefix.count {
                return String(path.dropFirst(prefix.count))
            }
        }
        return path
    }
}

private struct XccovReport: Decodable {
    let targets: [XccovTarget]
}

private struct XccovTarget: Decodable {
    let name: String
    let buildProductPath: String?
    let files: [XccovFile]
}

private struct XccovFile: Decodable {
    let path: String
    let coveredLines: Int
    let executableLines: Int
    let functions: [XccovFunction]?
}

private struct XccovFunction: Decodable {
    let name: String
    let lineNumber: Int
    let executionCount: Int
    let coveredLines: Int
    let executableLines: Int
}

private struct XccovLine: Decodable {
    let line: Int
    let isExecutable: Bool
    let executionCount: Int?
}
