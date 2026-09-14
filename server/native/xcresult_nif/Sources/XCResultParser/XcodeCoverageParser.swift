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
        let report: XccovReport? = try await fileSystem
            .runInTemporaryDirectory(prefix: "xcresult-coverage") { temporaryDirectory in
                let tempFile = temporaryDirectory.appending(component: "coverage.json")

                do {
                    _ = try await commandRunner.run(
                        arguments: [
                            "/bin/sh", "-c",
                            // `exec` replaces the shell with the tool so cancellation, which signals
                            // only the direct child, reaches xccov instead of orphaning it.
                            "exec /usr/bin/xcrun xccov view --report --json '\(resultBundlePath.pathString)' > '\(tempFile.pathString)'",
                        ]
                    ).concatenatedString()
                } catch let CommandError.terminated(_, stderr, _) where stderr.contains("No coverage data") {
                    // A run without `-enableCodeCoverage YES` writes no coverage archive, which is
                    // the common case rather than a failure.
                    return nil
                }

                let data = try await fileSystem.readFile(at: tempFile)
                return try JSONDecoder().decode(XccovReport.self, from: data)
            }

        guard let report else { return nil }

        return XcodeCoverageReport(
            targets: report.targets.map { target in
                XcodeCoverageTarget(
                    name: target.name,
                    coveredLines: target.coveredLines,
                    executableLines: target.executableLines,
                    files: target.files.map { file in
                        XcodeCoverageFile(
                            path: relativize(file.path, to: rootDirectory),
                            coveredLines: file.coveredLines,
                            executableLines: file.executableLines
                        )
                    }
                )
            }
        )
    }

    private func relativize(_ path: String, to rootDirectory: AbsolutePath?) -> String {
        guard let rootDirectory,
              let absolutePath = try? AbsolutePath(validating: path),
              absolutePath.isDescendant(of: rootDirectory)
        else { return path }
        return absolutePath.relative(to: rootDirectory).pathString
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
