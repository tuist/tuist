import Foundation
import Path
import TuistProcess

/// Copies files and directories between this machine and a sandbox, as `cp -r` would: into a destination that is an
/// existing directory, otherwise to the destination path, replacing what is there. Both directions move a gzipped tar
/// through a command's output or stdin, and place the result with a rename from a scratch directory next to the
/// destination, so a failed copy leaves the destination as it was.
struct SandboxCopy {
    let remote: SandboxRemote
    let commandRunner: CommandRunning

    /// - Parameter into: Copy into `local` as a directory even when it does not exist yet, such as for `out/`.
    /// - Returns: Where the copy ended up.
    func download(_ remotePath: String, to local: AbsolutePath, into: Bool) async throws -> AbsolutePath {
        var isDirectory: ObjCBool = false
        let into = into || FileManager.default.fileExists(atPath: local.pathString, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let containing = into ? local : local.parentDirectory
        try FileManager.default.createDirectory(atPath: containing.pathString, withIntermediateDirectories: true)
        let scratch = containing.appending(component: ".tuist-cp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: scratch.pathString, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: scratch.pathString) }
        let archive = scratch.appending(component: "copy.tar.gz")
        FileManager.default.createFile(atPath: archive.pathString, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: archive.pathString))
        defer { try? handle.close() }

        // COPYFILE_DISABLE keeps macOS's tar from adding AppleDouble `._` entries for extended attributes.
        let started = try await remote.start(
            #"set -eo pipefail; cd "$(dirname "$TUIST_PATH")"; tar -czf - "$(basename "$TUIST_PATH")" | base64"#,
            environment: ["TUIST_PATH": remotePath, "COPYFILE_DISABLE": "1"],
            timeoutMs: 60 * 60 * 1000
        )
        var decoder = Base64StreamDecoder()
        var stderr = ""
        let exit = try await remote.follow(started.id) { isStandardError, data in
            if isStandardError { stderr += data } else { try handle.write(contentsOf: decoder.decode(data)) }
        }
        guard exit.exitCode == 0 else {
            throw SandboxCommandError.stepFailed("Copying \(remotePath) from the sandbox", stderr)
        }
        try handle.write(contentsOf: decoder.finish())
        try handle.close()
        let extracted = scratch.appending(component: "extracted")
        try FileManager.default.createDirectory(atPath: extracted.pathString, withIntermediateDirectories: true)
        try await commandRunner.run(arguments: ["tar", "-xzf", archive.pathString, "-C", extracted.pathString])
            .awaitCompletion()
        guard let name = try FileManager.default.contentsOfDirectory(atPath: extracted.pathString).first else {
            throw SandboxCommandError.stepFailed("Copying \(remotePath) from the sandbox", "The archive was empty.")
        }

        let target = into ? local.appending(component: name) : local
        if FileManager.default.fileExists(atPath: target.pathString) {
            try FileManager.default.removeItem(atPath: target.pathString)
        }
        try FileManager.default.moveItem(atPath: extracted.appending(component: name).pathString, toPath: target.pathString)
        return target
    }

    /// - Returns: The absolute path the copy ended up at in the sandbox.
    func upload(_ source: AbsolutePath, to remotePath: String) async throws -> String {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tuist-sandbox-cp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archive = scratch.appendingPathComponent("copy.tar.gz")
        try await commandRunner.run(
            arguments: ["tar", "-czf", archive.path, "-C", source.parentDirectory.pathString, source.basename],
            environment: ProcessInfo.processInfo.environment.merging(["COPYFILE_DISABLE": "1"]) { $1 }
        ).awaitCompletion()

        let remoteArchive = "/tmp/tuist-cp-\(UUID().uuidString).tar.gz"
        try await remote.upload(archive, to: remoteArchive)
        let placed = try await remote.capture(
            #"""
            set -eu
            trap 'rm -rf "$TUIST_ARCHIVE" ${scratch:+"$scratch"}' EXIT
            case "$TUIST_DEST" in */) mkdir -p "$TUIST_DEST" ;; esac
            if [ -d "$TUIST_DEST" ]; then target="$TUIST_DEST/$TUIST_NAME"; else target="$TUIST_DEST"; fi
            parent="$(dirname "$target")"
            mkdir -p "$parent"
            scratch="$(mktemp -d "$parent/.tuist-cp.XXXXXX")"
            tar -xzf "$TUIST_ARCHIVE" -C "$scratch"
            rm -rf "$target"
            mv "$scratch/$TUIST_NAME" "$target"
            printf '%s' "$(cd "$parent" && pwd)/$(basename "$target")"
            """#,
            environment: ["TUIST_ARCHIVE": remoteArchive, "TUIST_DEST": remotePath, "TUIST_NAME": source.basename]
        )
        guard placed.exit.exitCode == 0 else {
            throw SandboxCommandError.stepFailed("Copying \(source.pathString) to the sandbox", placed.stderr)
        }
        return placed.stdout
    }
}
