import Foundation
import Path

/// Captures a macOS sandbox's iOS Simulator or screen as a PNG and writes it locally. One command takes the capture and
/// prints it as base64, so nothing is left behind in the sandbox, and the PNG replaces the destination with a rename
/// once it is complete.
struct SandboxScreenshot {
    struct Result: Codable, Equatable {
        let path: String
        let width: Int
        let height: Int
    }

    /// The script's exit statuses for failures the caller can act on.
    static let notMacOSStatus = 3
    static let noBootedSimulatorStatus = 4

    /// The capture tools' own output goes to stderr, so stdout carries only the image.
    static let script = #"""
    set -u
    [ "$(uname)" = Darwin ] || exit 3
    png="$(mktemp /tmp/tuist-screenshot.XXXXXX)"
    trap 'rm -f "$png"' EXIT
    if [ "$TUIST_TARGET" = screen ]; then
      screencapture -x -t png "$png" >&2 || exit 1
    else
      # simctl fails on a device that is not booted only after a long wait for its screen, so check first, by the
      # device's whole name or UDID.
      booted="$(xcrun simctl list devices booted | grep '(Booted)')"
      if [ "$TUIST_DEVICE" = booted ]; then [ -n "$booted" ] || exit 4
      else printf '%s\n' "$booted" | grep -qF -e "    $TUIST_DEVICE (" -e "($TUIST_DEVICE)" || exit 4; fi
      xcrun simctl io "$TUIST_DEVICE" screenshot --type=png "$png" >&2 || exit 1
    fi
    [ -s "$png" ] || { echo "The capture wrote no image." >&2; exit 1; }
    base64 < "$png"
    """#

    let remote: SandboxRemote

    func capture(_ target: SandboxScreenshotCommand.Target, device: String?, to local: AbsolutePath) async throws -> Result {
        try FileManager.default.createDirectory(atPath: local.parentDirectory.pathString, withIntermediateDirectories: true)
        let partial = local.parentDirectory.appending(component: ".\(local.basename).tuist-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: partial.pathString, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: partial.pathString) }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: partial.pathString))
        defer { try? handle.close() }

        let started = try await remote.start(
            Self.script,
            environment: ["TUIST_TARGET": target.rawValue, "TUIST_DEVICE": device ?? "booted"],
            timeoutMs: 2 * 60 * 1000
        )
        var decoder = Base64StreamDecoder()
        var stderr = ""
        var header = Data()
        let exit = try await remote.follow(started.id) { isStandardError, data in
            if isStandardError {
                stderr += data
            } else {
                let bytes = try decoder.decode(data)
                if header.count < 24 { header += bytes.prefix(24 - header.count) }
                try handle.write(contentsOf: bytes)
            }
        }
        switch exit.exitCode {
        case 0?: break
        case Self.notMacOSStatus?: throw SandboxCommandError.notMacOS
        case Self.noBootedSimulatorStatus?: throw SandboxCommandError.noBootedSimulator(device)
        default: throw SandboxCommandError.stepFailed("Taking the \(target.rawValue) screenshot", stderr)
        }
        let rest = try decoder.finish()
        if header.count < 24 { header += rest.prefix(24 - header.count) }
        try handle.write(contentsOf: rest)
        try handle.close()
        guard let (width, height) = Self.pngSize(header) else {
            throw SandboxCommandError.stepFailed("Taking the \(target.rawValue) screenshot", "The sandbox sent no PNG.")
        }
        if FileManager.default.fileExists(atPath: local.pathString) {
            try FileManager.default.removeItem(atPath: local.pathString)
        }
        try FileManager.default.moveItem(atPath: partial.pathString, toPath: local.pathString)
        return Result(path: local.pathString, width: width, height: height)
    }

    /// The width and height in a PNG's header: its signature, then the IHDR chunk, which starts with them.
    static func pngSize(_ header: Data) -> (Int, Int)? {
        let bytes = [UInt8](header.prefix(24))
        guard bytes.count == 24, bytes[0 ..< 8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            return nil
        }
        let number = { (start: Int) in bytes[start ..< start + 4].reduce(0) { $0 << 8 | Int($1) } }
        return (number(16), number(20))
    }
}
