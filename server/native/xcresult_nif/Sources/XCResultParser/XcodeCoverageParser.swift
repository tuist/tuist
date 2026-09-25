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
    /// Holds every entry in memory; for a large bundle prefer ``parse(resultBundlePath:manifest:into:)``.
    func parse(resultBundlePath: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport?

    /// The same, written to `output` as one JSON object per line (``XcodeCoverageFile``) while the
    /// bundle is read, so memory stays flat in the number of files and lines. Returns nil, and
    /// writes nothing, when the bundle carries no coverage data.
    func parse(
        resultBundlePath: AbsolutePath,
        manifest: XcodeCoverageManifest,
        into output: AbsolutePath
    ) async throws -> XcodeCoverageSummary?
}

/// What a streamed parse says about the bundle as a whole.
public struct XcodeCoverageSummary: Equatable, Sendable {
    public let partial: Bool
    public let fileCount: Int

    public init(partial: Bool, fileCount: Int) {
        self.partial = partial
        self.fileCount = fileCount
    }
}

public struct XcodeCoverageParser: XcodeCoverageParsing {
    private let fileSystem: FileSysteming
    private let execute: XCResultToolExecuting
    private let executeToFile: XCResultToolFileExecuting

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
        execute = executeXCResultTool
        executeToFile = executeXCResultTool(_:standardOutputTo:)
    }

    /// Runs xccov through `execute`; the reads that stream xccov's output from a file get it
    /// from `executeToFile`, or from `execute`'s output written to that file when none is given.
    public init(
        fileSystem: FileSysteming = FileSystem(),
        execute: @escaping XCResultToolExecuting,
        executeToFile: XCResultToolFileExecuting? = nil
    ) {
        self.fileSystem = fileSystem
        self.execute = execute
        self.executeToFile = executeToFile ?? { arguments, url in
            let output = try await execute(arguments)
            try Data(output.standardOutput.utf8).write(to: url)
            return output
        }
    }

    public func coveredFilePaths(resultBundlePath: AbsolutePath) async throws -> [String]? {
        try await xccov(["view", "--archive", "--file-list"], bundle: resultBundlePath).map { data in
            String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        }
    }

    public func parse(resultBundlePath: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport? {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage") { temporaryDirectory -> XcodeCoverageReport? in
            let output = temporaryDirectory.appending(component: "coverage.ndjson")
            guard let summary = try await parse(resultBundlePath: resultBundlePath, manifest: manifest, into: output)
            else { return nil }
            let files = try Self.readFiles(at: output).sorted { $0.path < $1.path }
            return XcodeCoverageReport(partial: summary.partial, files: files)
        }
    }

    public func parse(
        resultBundlePath: AbsolutePath,
        manifest: XcodeCoverageManifest,
        into output: AbsolutePath
    ) async throws -> XcodeCoverageSummary? {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage") { temporaryDirectory -> XcodeCoverageSummary? in
            let bundlePath = try await xcresultPath(for: resultBundlePath, temporaryDirectory: temporaryDirectory)
            let reportPath = temporaryDirectory.appending(component: "report.json")
            let archivePath = temporaryDirectory.appending(component: "archive.json")

            // The report carries the target and function hierarchy, the archive the per-line
            // execution counts; neither has what the other does. Both go to disk: the archive
            // alone is tens of megabytes for a mid-sized project and is only ever read one file
            // at a time from there.
            async let reportWritten = xccov(["view", "--report", "--json"], bundle: bundlePath, to: reportPath)
            async let archiveWritten = xccov(["view", "--archive", "--json"], bundle: bundlePath, to: archivePath)
            guard try await reportWritten, try await archiveWritten else { return nil }

            let decoder = JSONDecoder()
            let reportURL = URL(fileURLWithPath: reportPath.pathString)
            let archiveURL = URL(fileURLWithPath: archivePath.pathString)

            // Pass one over the report: which targets are test bundles, and which targets each
            // file is linked into. Names only; the functions stay on disk until their file's
            // turn.
            var testTargets = Set<String>()
            var targetsByPath: [String: [String]] = [:]
            try JSONStreamScanner.forEachElement(ofArrayAt: "targets", in: reportURL) { element in
                let target = try decoder.decode(XccovTargetOutline.self, from: element)
                if Self.isTestBundle(target.buildProductPath) { testTargets.insert(target.name) }
                for file in target.files where !(targetsByPath[file.path] ?? []).contains(target.name) {
                    targetsByPath[file.path, default: []].append(target.name)
                }
            }

            // The archive indexed by where each file's lines sit, so they are read back one
            // file at a time: the archive is the bulk of the data.
            var archiveIndex: [String: (offset: Int, length: Int)] = [:]
            try JSONStreamScanner.forEachMemberLocation(ofObjectAt: archiveURL) { path, offset, length in
                archiveIndex[path] = (offset, length)
            }

            let roots = Self.roots(manifest.rootDirectories)
            let blobIdsByPath = Dictionary(
                manifest.files.map { ($0.path, $0.gitBlobId) },
                uniquingKeysWith: { first, _ in first }
            )
            // Only the repository's own code counts: third-party packages compiled with instrumentation
            // (checkouts under `.build` or DerivedData) would dominate both the figure and the payload.
            // In a Git checkout the manifest lists the covered files Git does not ignore, which leaves
            // out ignored build and checkout directories too.
            let repositoryPaths = Set(manifest.files.map(\.path))

            guard FileManager.default.createFile(atPath: output.pathString, contents: nil) else {
                throw XcodeCoverageParserError.cannotWrite(output)
            }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output.pathString))
            defer { try? handle.close() }
            let encoder = JSONEncoder()
            var emitted = Set<String>()
            var fileCount = 0

            func emit(_ absolutePath: String, reported: XccovFile?) throws {
                emitted.insert(absolutePath)
                let path = Self.relativize(absolutePath, to: roots)
                guard !path.hasPrefix("/"), !Self.isDependencyPath(path),
                      repositoryPaths.isEmpty || repositoryPaths.contains(path)
                else { return }
                var lines: [XccovLine] = []
                if let location = archiveIndex[absolutePath] {
                    let data = try JSONStreamScanner.value(at: location.offset, length: location.length, in: archiveURL)
                    lines = try decoder.decode([XccovLine].self, from: data).filter(\.isExecutable).sorted { $0.line < $1.line }
                }
                let counts = lines.map { $0.executionCount ?? 0 }
                let targets = targetsByPath[absolutePath] ?? []
                let productTargets = targets.filter { !testTargets.contains($0) }
                let isTest = !targets.isEmpty && productTargets.isEmpty
                // Test code is left out of every figure, so only its counts travel.
                let file = XcodeCoverageFile(
                    path: path,
                    gitBlobId: blobIdsByPath[path],
                    targets: productTargets.isEmpty ? targets : productTargets,
                    isTest: isTest,
                    coveredLines: lines.isEmpty ? reported?.coveredLines ?? 0 : counts.filter { $0 > 0 }.count,
                    executableLines: lines.isEmpty ? reported?.executableLines ?? 0 : lines.count,
                    lineNumbers: isTest ? [] : lines.map(\.line),
                    executionCounts: isTest ? [] : counts,
                    functions: isTest ? [] : (reported?.functions ?? []).map {
                        XcodeCoverageFunction(
                            name: $0.name,
                            lineNumber: $0.lineNumber,
                            executionCount: $0.executionCount,
                            coveredLines: $0.coveredLines,
                            executableLines: $0.executableLines
                        )
                    }
                )
                try autoreleasepool {
                    try handle.write(contentsOf: try encoder.encode(file))
                    try handle.write(contentsOf: Data([UInt8(ascii: "\n")]))
                }
                fileCount += 1
            }

            // Pass two over the report, one target at a time: a file linked into several targets
            // is listed under each with the same functions, so its first listing emits it.
            try JSONStreamScanner.forEachElement(ofArrayAt: "targets", in: reportURL) { element in
                let target = try decoder.decode(XccovTarget.self, from: element)
                for file in target.files where !emitted.contains(file.path) {
                    try emit(file.path, reported: file)
                }
            }
            // A file the archive has lines for that the report never listed.
            for absolutePath in archiveIndex.keys.sorted() where !emitted.contains(absolutePath) {
                try emit(absolutePath, reported: nil)
            }

            return XcodeCoverageSummary(partial: manifest.partial, fileCount: fileCount)
        }
    }

    /// The files of a streamed parse's output, one per line.
    public static func readFiles(at path: AbsolutePath) throws -> [XcodeCoverageFile] {
        let decoder = JSONDecoder()
        return try Data(contentsOf: URL(fileURLWithPath: path.pathString))
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { try decoder.decode(XcodeCoverageFile.self, from: $0) }
    }

    /// Runs xccov against the bundle and writes what it prints to `destination`, returning
    /// false when the bundle has no coverage to read, which is the case for every run that did
    /// not enable it.
    private func xccov(_ arguments: [String], bundle: AbsolutePath, to destination: AbsolutePath) async throws -> Bool {
        guard FileManager.default.createFile(atPath: destination.pathString, contents: nil) else {
            throw XcodeCoverageParserError.cannotWrite(destination)
        }
        // Spawned directly rather than through a shell: the bundle path is user-controlled
        // and goes through as one argument, so no quoting is involved.
        let output = try await executeToFile(
            ["/usr/bin/xcrun", "xccov"] + arguments + [bundle.pathString],
            URL(fileURLWithPath: destination.pathString)
        )
        if output.succeeded { return true }
        if Self.reportsNoCoverage(output.standardError) { return false }
        throw XCResultParserError.failedToParseOutput(bundle)
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
    static func roots(_ rootDirectories: [String]) -> [String] {
        rootDirectories
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .filter { $0.hasPrefix("/") }
            .sorted { $0.count > $1.count }
    }

    /// Plain string prefixes: the manifest already lists every spelling of the root the build
    /// could have used, and whoever processes the bundle may not have the checkout to resolve
    /// anything against.
    static func relativize(_ path: String, to roots: [String]) -> String {
        for root in roots {
            let prefix = root == "/" ? root : root + "/"
            if path.hasPrefix(prefix), path.count > prefix.count {
                return String(path.dropFirst(prefix.count))
            }
        }
        return path
    }
}

enum XcodeCoverageParserError: Error, LocalizedError {
    case cannotWrite(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .cannotWrite(path): "Could not write the coverage to \(path.pathString)"
        }
    }
}

private struct XccovTarget: Decodable {
    let name: String
    let buildProductPath: String?
    let files: [XccovFile]
}

/// A target's names alone, for the pass that only maps files to targets.
private struct XccovTargetOutline: Decodable {
    struct File: Decodable {
        let path: String
    }

    let name: String
    let buildProductPath: String?
    let files: [File]
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
