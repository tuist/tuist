import Command
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
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
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

        let files = Set(archive.keys).union(targetsByPath.keys).map { absolutePath in
            let path = Self.relativize(absolutePath, to: roots)
            let lines = (archive[absolutePath] ?? []).filter(\.isExecutable).sorted { $0.line < $1.line }
            let counts = lines.map { $0.executionCount ?? 0 }
            let reported = countsByPath[absolutePath]
            return XcodeCoverageFile(
                path: path,
                gitBlobId: blobIdsByPath[path],
                targets: targetsByPath[absolutePath] ?? [],
                coveredLines: lines.isEmpty ? reported?.covered ?? 0 : counts.filter { $0 > 0 }.count,
                executableLines: lines.isEmpty ? reported?.executable ?? 0 : lines.count,
                lineNumbers: lines.map(\.line),
                executionCounts: counts,
                functions: functionsByPath[absolutePath] ?? []
            )
        }.sorted { $0.path < $1.path }

        let observedPaths = Set(files.map(\.path))
        return XcodeCoverageReport(
            partial: manifest.partial,
            files: files,
            unobservedFiles: manifest.partial ? manifest.files.filter { !observedPaths.contains($0.path) } : []
        )
    }

    /// Runs xccov against the bundle and returns what it printed, or nil when the bundle has no
    /// coverage to read, which is the case for every run that did not enable it.
    private func xccov(_ arguments: [String], bundle: AbsolutePath) async throws -> Data? {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage") { temporaryDirectory -> Data? in
            let bundlePath = try await xcresultPath(for: bundle, temporaryDirectory: temporaryDirectory)
            do {
                // Spawned directly rather than through a shell: the bundle path is user-controlled
                // and goes through as one argument, so no quoting is involved.
                return try await commandRunner
                    .run(arguments: ["/usr/bin/xcrun", "xccov"] + arguments + [bundlePath.pathString])
                    .reduce(into: Data()) { data, event in
                        if case let .standardOutput(bytes) = event { data.append(contentsOf: bytes) }
                    }
            } catch let CommandError.terminated(_, stderr, _) where Self.reportsNoCoverage(stderr) {
                return nil
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
