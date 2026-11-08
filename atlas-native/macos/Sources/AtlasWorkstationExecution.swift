#if os(macOS)
import Darwin
import Foundation

enum AtlasWorkstationExecution {
    static func perform(
        _ command: AtlasWorkstationCommand, root: URL, progress: AtlasWorkstationProgress = AtlasWorkstationProgress()
    ) async -> AtlasWorkstationResult {
        let process = WorkstationProcess(progress: progress)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let result: AtlasWorkstationResult
                    do {
                        switch command.tool {
                        case "environment_read_file":
                            result = try read(command.arguments.path ?? "", root: root)
                        case "environment_list_directory":
                            result = try list(command.arguments.path ?? "", root: root)
                        case "environment_terminal", "bash":
                            result = try process.run(command.arguments.command ?? "", root: root,
                                                     timeout: command.arguments.timeout ?? 1800)
                        case "read", "edit", "write":
                            result = try AtlasWorkstationFiles.perform(command, root: root)
                        default:
                            result = AtlasWorkstationResult(
                                success: false, output: "This tool is unavailable on this Mac."
                            )
                        }
                    } catch {
                        result = AtlasWorkstationResult(
                            success: false, output: "Could not access the file or run this tool. " +
                                "Use a contained UTF-8 file (maximum 4 MiB); write parents must exist."
                        )
                    }
                    continuation.resume(returning: result)
                }
            }
        } onCancel: { process.cancel() }
    }

    static func resolve(_ path: String, root: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw CocoaError(.fileReadNoPermission)
        }
        let root = try canonical(root)
        let target = try canonical(root.appendingPathComponent(path))
        guard contains(target, in: root) else { throw CocoaError(.fileReadNoPermission) }
        return target
    }

    private static func canonical(_ url: URL) throws -> URL {
        guard let path = realpath(url.path, nil) else { throw CocoaError(.fileReadNoPermission) }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }

    private static func contains(_ target: URL, in root: URL) -> Bool {
        target.path == root.path || target.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }

    private static func read(_ path: String, root: URL) throws -> AtlasWorkstationResult {
        let target = try resolve(path, root: root)
        let descriptor = Darwin.open(target.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        var actual = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= 48 * 1024, fcntl(descriptor, F_GETPATH, &actual) == 0,
              try contains(canonical(URL(fileURLWithPath: String(cString: actual))), in: canonical(root)) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: 48 * 1024 + 1) ?? Data()
        guard data.count <= 48 * 1024, let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            return AtlasWorkstationResult(success: false, output: "Choose a UTF-8 text file no larger than 48 KiB.")
        }
        return AtlasWorkstationResult(success: true, output: text)
    }

    private static func list(_ path: String, root: URL) throws -> AtlasWorkstationResult {
        let target = try resolve(path, root: root)
        let descriptor = Darwin.open(target.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var actual = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &actual) == 0,
              let actualURL = try? canonical(URL(fileURLWithPath: String(cString: actual))),
              let rootURL = try? canonical(root), contains(actualURL, in: rootURL),
              let directory = fdopendir(descriptor) else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadNoPermission)
        }
        defer { closedir(directory) }
        var rows: [[String: Any]] = []
        var inspected = 0
        var truncated = false
        while let entry = readdir(directory) {
            inspected += 1
            if inspected > 1000 || rows.count == 100 { truncated = true; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard !name.hasPrefix(".") else { continue }
            var metadata = stat()
            guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            rows.append(["name": name, "directory": metadata.st_mode & S_IFMT == S_IFDIR,
                         "symbolic_link": metadata.st_mode & S_IFMT == S_IFLNK])
        }
        rows.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        let data = try JSONSerialization.data(withJSONObject: ["entries": rows, "truncated": truncated])
        guard data.count <= 48 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadTooLarge)
        }
        return AtlasWorkstationResult(success: true, output: text)
    }
}

private final class WorkstationProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: AtlasWorkstationProgress
    private var pid: pid_t = 0
    private var cancelled = false

    init(progress: AtlasWorkstationProgress) { self.progress = progress }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if pid > 0 { kill(-pid, SIGKILL) }
    }

    func run(_ command: String, root: URL, timeout: Int) throws -> AtlasWorkstationResult {
        guard !command.isEmpty, command.utf8.count <= 8000, !command.contains("\0"), (1...1800).contains(timeout) else {
            throw CocoaError(.executableNotLoadable)
        }
        var descriptors = [Int32](repeating: 0, count: 2)
        guard pipe(&descriptors) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptors[0]) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addchdir_np(&actions, root.path)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        posix_spawn_file_actions_addclose(&actions, descriptors[1])
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        // An independent deadline also survives an app crash. The command is a
        // positional argument, never interpolated into the watchdog's source.
        let wrapper = "(sleep \"$2\"; kill -KILL -- -$$) </dev/null >/dev/null 2>&1 & exec /bin/zsh -f -c \"$1\""
        let arguments: [UnsafeMutablePointer<CChar>?] = [
            "/bin/sh", "-c", wrapper, "atlas-tool", command, String(timeout)
        ]
            .map { $0.withCString { strdup($0) } } + [nil]
        let environment: [UnsafeMutablePointer<CChar>?] = [
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME=\(NSHomeDirectory())",
            "TMPDIR=\(NSTemporaryDirectory())", "LANG=en_US.UTF-8"
        ]
            .map { $0.withCString { strdup($0) } } + [nil]
        defer { arguments.forEach { free($0) }; environment.forEach { free($0) } }
        lock.lock()
        if cancelled { lock.unlock(); close(descriptors[1]); throw CancellationError() }
        var child: pid_t = 0
        let spawned = arguments.withUnsafeBufferPointer { args in
            environment.withUnsafeBufferPointer { env in
                posix_spawn(&child, "/bin/sh", &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        if spawned == 0 { pid = child }
        lock.unlock()
        close(descriptors[1])
        guard spawned == 0 else { throw CocoaError(.executableNotLoadable) }
        defer { lock.lock(); pid = 0; lock.unlock() }
        let deadline = DispatchSource.makeTimerSource()
        deadline.schedule(deadline: .now() + .seconds(timeout))
        deadline.setEventHandler { [weak self] in self?.cancel() }
        deadline.resume()
        defer { deadline.cancel() }
        return collectOutput(descriptors[0], child: child)
    }

    private func collectOutput(_ descriptor: Int32, child: pid_t) -> AtlasWorkstationResult {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            if count <= 0 { break }
            progress.append(buffer.prefix(count))
        }
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0, errno == EINTR {}
        kill(-child, SIGKILL)
        guard let text = progress.text else {
            return AtlasWorkstationResult(
                success: false, output: "Command output was not UTF-8; binary output was not sent."
            )
        }
        lock.lock()
        let stopped = cancelled
        lock.unlock()
        let suffix = stopped ? "\n[Command stopped by cancellation or its execution limit.]" : ""
        return AtlasWorkstationResult(success: status == 0 && !stopped,
                                      output: text + suffix)
    }
}

final class AtlasWorkstationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var truncated = false

    var text: String? {
        lock.lock()
        defer { lock.unlock() }
        // A byte-bounded tail can begin inside a UTF-8 scalar.
        let bytes = truncated ? output.drop(while: { $0 & 0xC0 == 0x80 }) : output[...]
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        return (truncated ? "[Earlier output omitted; showing the latest output.]\n" : "") + text
    }

    fileprivate func append(_ bytes: ArraySlice<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        output.append(contentsOf: bytes)
        let limit = 48 * 1024 - 256
        if output.count > limit {
            output = Data(output.suffix(limit))
            truncated = true
        }
    }
}
#endif
