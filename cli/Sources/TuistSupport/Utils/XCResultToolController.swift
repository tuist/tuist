import Command
import Mockable
import Path

import struct TSCUtility.Version

@Mockable
public protocol XCResultToolControlling {
    func resultBundleObject(_ path: AbsolutePath) async throws -> String
    func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String
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
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json", "--legacy",
                ]
            )
            .concatenatedString()
        } else {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json",
                ]
            )
            .concatenatedString()
        }
    }

    public func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String {
        if try await XcodeController.current.selectedVersion() >= Version(16, 0, 0) {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json", "--legacy",
                ]
            )
            .concatenatedString()
        } else {
            return try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json",
                ]
            )
            .concatenatedString()
        }
    }
}
