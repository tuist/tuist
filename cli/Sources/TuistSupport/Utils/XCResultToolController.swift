import Mockable
import Path

import struct TSCUtility.Version

@Mockable
public protocol XCResultToolControlling {
    func resultBundleObject(_ path: AbsolutePath) async throws -> String
    func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String
}

public final class XCResultToolController: XCResultToolControlling {
    private let system: Systeming

    public init(
        system: Systeming = System.shared
    ) {
        self.system = system
    }

    public func resultBundleObject(_ path: AbsolutePath) async throws -> String {
        if try await XcodeController.current.selectedVersion() >= Version(16, 0, 0) {
            return try system.capture(
                [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json", "--legacy",
                ]
            )
        } else {
            return try system.capture(
                [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--format",
                    "json",
                ]
            )
        }
    }

    public func resultBundleObject(_ path: AbsolutePath, id: String) async throws -> String {
        if try await XcodeController.current.selectedVersion() >= Version(16, 0, 0) {
            return try system.capture(
                [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json", "--legacy",
                ]
            )
        } else {
            return try system.capture(
                [
                    "/usr/bin/xcrun", "xcresulttool", "get", "--path", path.pathString, "--id", id,
                    "--format", "json",
                ]
            )
        }
    }
}
