#if os(macOS)
import CryptoKit
import Foundation

/// Local paths never cross the environment registration boundary. Worktrees are
/// retained on archive/sign-out: deleting a conversation must not delete code.
actor AtlasWorkstationWorktrees {
    private var preparing: [String: Task<URL, Error>] = [:]

    func directory(for command: AtlasWorkstationCommand, repository: URL, scope: String) async throws -> URL {
        guard let threadId = command.arguments.threadId, UUID(uuidString: threadId) != nil,
              UUID(uuidString: command.arguments.projectId) != nil else { throw CocoaError(.coderInvalidValue) }
        let scopeId = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(scopeId)/\(command.arguments.projectId)/\(threadId)"
        if let task = preparing[key] { return try await task.value }
        let task = Task.detached(priority: .utility) {
            let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Atlas/Worktrees/\(key)")
            return try Self.prepare(repository: repository, directory: base, threadId: threadId,
                                    title: command.arguments.title ?? "Coding")
        }
        preparing[key] = task
        defer { preparing.removeValue(forKey: key) }
        return try await task.value
    }

    static func prepare(repository: URL, directory: URL, threadId: String, title: String) throws -> URL {
        guard UUID(uuidString: threadId) != nil else { throw CocoaError(.coderInvalidValue) }
        let repository = repository.resolvingSymlinksInPath()
        let top = try git(["rev-parse", "--show-toplevel"], in: repository)
        guard URL(fileURLWithPath: top).resolvingSymlinksInPath() == repository else {
            throw CocoaError(.fileReadNoPermission)
        }
        let common = try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repository)
        if FileManager.default.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true,
                  try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: directory) == common,
                  URL(fileURLWithPath: try git(["rev-parse", "--show-toplevel"], in: directory))
                    .resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() else {
                throw CocoaError(.fileReadNoPermission)
            }
            return directory
        }
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let slug = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .prefix(48).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let branch = "atlas/\(slug.isEmpty ? "coding" : slug)-\(threadId.lowercased())"
        // No fetch, reset, stash or force. Start from local HEAD and leave the
        // person's original branch and dirty files untouched.
        _ = try git(["worktree", "add", "-b", branch, "--", directory.path, "HEAD"], in: repository)
        return directory
    }

    private static func git(_ arguments: [String], in root: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.hooksPath=/dev/null"] + arguments
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Only rev-parse emits captured output. Checkout progress cannot fill a pipe.
        process.standardOutput = arguments.first == "rev-parse" ? output.fileHandleForWriting : FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw CocoaError(.executableRuntimeMismatch)
        }
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        guard arguments.first == "rev-parse" else { return "" }
        try output.fileHandleForWriting.close()
        let data = try output.fileHandleForReading.read(upToCount: 8192) ?? Data()
        guard data.count < 8192, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text.trimmingCharacters(in: .newlines)
    }
}
#endif
