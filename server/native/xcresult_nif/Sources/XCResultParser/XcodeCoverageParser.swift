import Command
import FileSystem
import Foundation
import Mockable
import Path

@Mockable
public protocol XcodeCoverageParsing: Sendable {
    /// Reads the coverage report `xcodebuild` wrote into the result bundle.
    ///
    /// Returns nil when the bundle carries no coverage data, which is the case
    /// for every run that did not enable code coverage. Paths are relativized
    /// against `rootDirectory` when they live under it.
    func parse(resultBundlePath: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> XcodeCoverageReport?
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

    public func parse(resultBundlePath: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> XcodeCoverageReport? {
        let output: String? = try await fileSystem
            .runInTemporaryDirectory(prefix: "xcode-coverage") { temporaryDirectory -> String? in
                let bundlePath = try await xcresultPath(for: resultBundlePath, temporaryDirectory: temporaryDirectory)
                do {
                    // Spawned directly rather than through a shell: the bundle path is user-controlled
                    // and goes through as one argument, so no quoting is involved.
                    return try await commandRunner.run(
                        arguments: ["/usr/bin/xcrun", "xccov", "view", "--report", "--json", bundlePath.pathString]
                    ).concatenatedString(including: [.standardOutput])
                } catch let CommandError.terminated(_, stderr, _) where Self.reportsNoCoverage(stderr) {
                    // A run without `-enableCodeCoverage YES` writes no coverage archive, which is the
                    // common case rather than a failure.
                    return nil
                }
            }

        guard let output else { return nil }

        let report = try JSONDecoder().decode(XccovReport.self, from: Data(output.utf8))
        let root = rootDirectory.map(Self.canonical)

        return XcodeCoverageReport(
            targets: report.targets.map { target in
                XcodeCoverageTarget(
                    name: target.name,
                    coveredLines: target.coveredLines,
                    executableLines: target.executableLines,
                    files: target.files.map { file in
                        XcodeCoverageFile(
                            path: Self.relativize(file.path, to: root),
                            coveredLines: file.coveredLines,
                            executableLines: file.executableLines
                        )
                    }
                )
            }
        )
    }

    /// xccov identifies a bundle by its `.xcresult` extension and refuses anything else with
    /// "unrecognized file format". `xcodebuild -resultBundlePath <name>` without an extension
    /// writes `<name>.xcresult` and leaves `<name>` as a symlink to it, which is what Tuist's
    /// default result bundle path looks like, so follow the link; a bundle that really has no
    /// extension is reached through a temporary link that has one.
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

    /// The root is canonicalized once; xccov reports real paths, so a prefix check settles
    /// almost every file without touching the filesystem, and only a file outside that prefix
    /// pays for its own canonicalization (a checkout reached through a link, `/tmp` being
    /// `/private/tmp` on macOS).
    private static func relativize(_ path: String, to root: AbsolutePath?) -> String {
        guard let root, path.hasPrefix("/") else { return path }
        let resolved = path.hasPrefix(root.pathString + "/") ? path : canonical(path)
        guard let absolutePath = try? AbsolutePath(validating: resolved),
              absolutePath.isDescendant(of: root)
        else { return path }
        return absolutePath.relative(to: root).pathString
    }

    /// `realpath` of the longest existing prefix with the rest appended, so a file the report
    /// names but the checkout no longer has still canonicalizes through the directories that
    /// exist. Foundation's `resolvingSymlinksInPath` is avoided: it strips `/private` from some
    /// paths and not others, which is the very mismatch this guards against. Only absolute
    /// paths are walked; `deletingLastPathComponent` never reaches "/" from a relative one.
    private static func canonical(_ path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        var existing = path
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing), existing != "/" {
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        guard let resolved = realpath(existing, nil) else { return path }
        defer { free(resolved) }
        return ([String(cString: resolved)] + rest).joined(separator: "/")
    }

    private static func canonical(_ path: AbsolutePath) -> AbsolutePath {
        (try? AbsolutePath(validating: canonical(path.pathString))) ?? path
    }
}

private struct XccovReport: Decodable {
    let targets: [XccovTarget]
}

private struct XccovTarget: Decodable {
    let name: String
    let coveredLines: Int
    let executableLines: Int
    let files: [XccovFile]
}

private struct XccovFile: Decodable {
    let path: String
    let coveredLines: Int
    let executableLines: Int
}
