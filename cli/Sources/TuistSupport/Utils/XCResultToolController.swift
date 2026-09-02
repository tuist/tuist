import Command
import Mockable
import Path

import struct TSCUtility.Version

@Mockable
public protocol XCResultToolControlling {
    func resultBundleObject(_ path: AbsolutePath) async throws -> String
    func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String
    func merge(_ resultBundlePaths: [AbsolutePath], into resultBundlePath: AbsolutePath) async throws
    func verifyReadable(_ resultBundlePath: AbsolutePath) async throws
}

public struct XCResultToolController: XCResultToolControlling {
    private let commandRunner: CommandRunning

    public init(
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.commandRunner = commandRunner
    }

    public func resultBundleObject(_ path: AbsolutePath) async throws -> String {
        if try await XcodeController.current.selectedVersion() >= Version(16, 0, 0) {
            return try await commandRunner.capture(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json", "--legacy",
                ]
            )
        } else {
            return try await commandRunner.capture(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json",
                ]
            )
        }
    }

    public func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String {
        if try await XcodeController.current.selectedVersion() >= Version(16, 0, 0) {
            return try await commandRunner.capture(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json", "--legacy",
                ]
            )
        } else {
            return try await commandRunner.capture(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json",
                ]
            )
        }
    }

    /// Reads the bundle's test-results summary, which fails when the bundle has
    /// no `Info.plist` or its manifest references objects the bundle does not
    /// contain. It walks the same object graph the server reads but returns
    /// only the summary, and a bundle that ran no tests still reads cleanly.
    public func verifyReadable(_ resultBundlePath: AbsolutePath) async throws {
        _ = try await commandRunner.capture(
            arguments: [
                "/usr/bin/xcrun", "xcresulttool", "get", "test-results", "summary",
                "--path", resultBundlePath.pathString,
            ]
        )
    }

    public func merge(_ resultBundlePaths: [AbsolutePath], into resultBundlePath: AbsolutePath) async throws {
        _ = try await commandRunner.capture(
            arguments: ["/usr/bin/xcrun", "xcresulttool", "merge"]
                + resultBundlePaths.map(\.pathString)
                + ["--output-path", resultBundlePath.pathString]
        )
    }
}
