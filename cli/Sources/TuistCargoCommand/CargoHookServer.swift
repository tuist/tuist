import Crypto
import Foundation
import Path
import TuistProcess
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Serves compiler hooks from the outer `tuist cargo` process, like cas-plugin's proxy serves its compiler plugin:
/// Cargo starts a small native client (`client`) for every rustc, and the client asks this server, over a private
/// Unix socket, what to do. The cache logic stays here in Swift and keeps its state across hooks; the client only
/// starts, so no compilation pays for loading the Swift runtime and the full Tuist binary.
///
/// The client stays the parent of rustc: rustc inherits Cargo's jobserver descriptors, standard input and process
/// group from it, which a compiler started by this process could not. On a miss the server returns the command and
/// environment to run, the client streams rustc's standard error back and forwards what the server returns (Cargo
/// pipelines dependents on rustc's metadata notification, which the server certifies first), then reports rustc's
/// exit status for publication. A client that cannot reach the server runs `tuist cargo __compiler` instead.
///
/// Build-script shims start the same client as `cargo __script <script> <arguments>`, which sends an `S` request for
/// the script's arguments, so a cached run replays without the Swift runtime too. The `cc` shim starts it as
/// `cargo __native <cc> <arguments>`, an `N` request decided like `tuist cargo __native` would.
///
/// Frames are a tag byte and a little-endian 32-bit length. Client to server: `Q` compiler, `S` build-script or `N`
/// native compiler request (working directory, then counted NUL-terminated arguments and environment), `o`/`e`
/// compiler output, `x` exit status. Server to client: `O`/`E` output to write, `R` command to run (counted arguments
/// and environment), `X` exit status to exit with, `F` fall back.
final class CargoHookServer: @unchecked Sendable {
    static let version = "tuist-cargo-hook-v3"
    static let socketVariable = "TUIST_CARGO_HOOK_SOCKET"
    static let fallbackVariable = "TUIST_CARGO_HOOK_FALLBACK"
    /// The client the `cc` shim starts in a served session.
    static let nativeVariable = "TUIST_CARGO_NATIVE"

    let socketPath: String
    private let directory: String
    private let listener: Int32
    private let runner: CommandRunning
    private let stopped = NSLock()
    private var isStopped = false
    private var acceptor: Thread?
    /// The session's REAPI connection, shared by every hook served.
    private let remote: Task<(any REAPICacheStoring)?, Never>?

    /// Builds the client once per cache directory. `nil` when unsupported or unavailable.
    static func client(cacheDirectory: URL) -> URL? {
        #if os(macOS)
            let identity = SHA256.hash(data: Data((version + source).utf8)).map { String(format: "%02x", $0) }.joined()
            let directory = cacheDirectory.appendingPathComponent("hook")
            let client = directory.appendingPathComponent("rustc-\(identity.prefix(16))")
            if FileManager.default.isExecutableFile(atPath: client.path) { return client }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let staging = directory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                let file = staging.appendingPathComponent("hook.c")
                try Data(source.utf8).write(to: file)
                let output = staging.appendingPathComponent("hook")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["clang", "-O2", "-o", output.path, file.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                // A rename is atomic, so concurrent sessions either find the finished client or install the same one.
                if rename(output.path, client.path) != 0, !FileManager.default.isExecutableFile(atPath: client.path) {
                    return nil
                }
                return client
            } catch { return nil }
        #else
            return nil
        #endif
    }

    /// Listens on a socket in a new private directory (short enough for `sun_path`, unlike the session directory).
    init?(runner: CommandRunning, remote: Task<(any REAPICacheStoring)?, Never>?) {
        var template = Array("/tmp/tuist-cargo-XXXXXX".utf8CString)
        guard let created = mkdtemp(&template) else { return nil }
        directory = String(cString: created)
        socketPath = directory + "/hook"
        self.runner = runner
        self.remote = remote
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { rmdir(directory); return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        #if canImport(Darwin)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
            let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { rmdir(directory); return nil }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 256) == 0 else { close(fd); rmdir(directory); return nil }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        listener = fd
    }

    func start() {
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "tuist-cargo-hook"
        acceptor = thread
        thread.start()
    }

    /// Stops accepting. Cargo has exited by then, so no client is still waiting.
    func stop() {
        stopped.lock()
        isStopped = true
        stopped.unlock()
        unlink(socketPath)
        rmdir(directory)
    }

    private var shouldStop: Bool {
        stopped.lock()
        defer { stopped.unlock() }
        return isStopped
    }

    private func acceptLoop() {
        defer { close(listener) }
        var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        while !shouldStop {
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { continue }
            _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
            #if canImport(Darwin)
                var on: Int32 = 1
                setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            #endif
            // Each hook blocks on its compiler for seconds; a thread of its own keeps that off Swift's
            // cooperative pool, which the cache work itself runs on.
            let thread = Thread { [self] in serve(connection) }
            thread.stackSize = 4 << 20
            thread.start()
        }
    }

    // MARK: - One hook

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        guard let (tag, payload) = Self.read(connection), [UInt8(ascii: "Q"), UInt8(ascii: "S"), UInt8(ascii: "N")].contains(tag),
              let request = Self.request(payload) else { return }
        let run: (any CargoHookRun)?
        if tag == UInt8(ascii: "S") {
            // A build-script run: the shim passes the real script, then the script's own arguments.
            switch Self.wait({ [runner, remote] in
                await CargoBuildScript.decide(
                    real: request.arguments[0], arguments: Array(request.arguments.dropFirst()),
                    environment: request.environment, directory: request.directory, runner: runner, sessionRemote: remote
                )
            }) {
            case let .replayed(stdout, stderr):
                _ = Self.write(connection, "O", stdout) && Self.write(connection, "E", stderr)
                    && Self.write(connection, "X", Self.status(0))
                return
            case let .run(script): run = script
            }
        } else {
            let observer = CargoCompilerObserver(runner: runner, sessionRemote: remote)
            switch Self.wait({
                try? await observer.decide(
                    request.arguments, environment: request.environment, directory: request.directory,
                    native: tag == UInt8(ascii: "N")
                )
            }) {
            case nil: run = nil
            case let .replayed(stdout, stderr)?:
                _ = Self.write(connection, "O", stdout) && Self.write(connection, "E", stderr)
                    && Self.write(connection, "X", Self.status(0))
                return
            case let .compile(compilation)?: run = compilation
            }
        }
        guard let run else {
            _ = Self.write(connection, "F", Data())
            return
        }
        guard Self.write(connection, "R", Self.encode(run.command, run.environment.map { "\($0.key)=\($0.value)" })) else {
            Self.wait { await run.finish(succeeded: false) }
            return
        }
        var status: Int32 = 1
        loop: while let (tag, bytes) = Self.read(connection) {
            switch tag {
            case UInt8(ascii: "o"): run.standardOutput(bytes)
            case UInt8(ascii: "e"):
                guard Self.write(connection, "E", run.standardError(bytes)) else { break loop }
            case UInt8(ascii: "x"):
                status = bytes.count == 4 ? bytes
                    .withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) } : 1
                break loop
            default: break loop
            }
        }
        Self.wait { await run.finish(succeeded: status == 0) }
        _ = Self.write(connection, "X", Self.status(status))
    }

    /// Runs async cache work from a hook's thread, which may block, without holding a cooperative thread meanwhile.
    @discardableResult
    private static func wait<T>(_ body: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box<T>()
        Task {
            box.value = await body()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }

    private final class Box<T>: @unchecked Sendable { var value: T? }

    private struct Request {
        let directory: AbsolutePath
        let arguments: [String]
        let environment: [String: String]
    }

    private static func request(_ payload: Data) -> Request? {
        var fields = payload.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        guard fields.count >= 3, let directory = try? AbsolutePath(validating: fields.removeFirst()),
              let count = Int(fields.removeFirst()), count >= 1, fields.count >= count + 1 else { return nil }
        let arguments = Array(fields.prefix(count))
        fields.removeFirst(count)
        guard let variables = Int(fields.removeFirst()), fields.count >= variables else { return nil }
        var environment: [String: String] = [:]
        for entry in fields.prefix(variables) {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return Request(directory: directory, arguments: arguments, environment: environment)
    }

    private static func encode(_ arguments: [String], _ environment: [String]) -> Data {
        var data = Data()
        for field in ["\(arguments.count)"] + arguments + ["\(environment.count)"] + environment {
            data.append(contentsOf: Array(field.utf8) + [UInt8(0)])
        }
        return data
    }

    private static func status(_ code: Int32) -> Data {
        withUnsafeBytes(of: code.littleEndian) { Data($0) }
    }

    private static func read(_ fd: Int32) -> (UInt8, Data)? {
        guard let header = readExactly(fd, 5) else { return nil }
        let length = header.dropFirst().withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length <= 64_000_000, let payload = readExactly(fd, Int(length)) else { return nil }
        return (header[header.startIndex], payload)
    }

    private static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + offset, count - offset, 0) }
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { return nil }
            offset += received
        }
        return data
    }

    private static func write(_ fd: Int32, _ tag: Character, _ payload: Data) -> Bool {
        var frame = Data([tag.asciiValue!])
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Array($0) })
        frame.append(payload)
        var offset = 0
        while offset < frame.count {
            let sent = frame.withUnsafeBytes { send(fd, $0.baseAddress! + offset, frame.count - offset, 0) }
            if sent < 0, errno == EINTR { continue }
            guard sent > 0 else { return false }
            offset += sent
        }
        return true
    }

    // MARK: - Client

    static let source = #"""
    #include <errno.h>
    #include <fcntl.h>
    #include <poll.h>
    #include <spawn.h>
    #include <stdint.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/socket.h>
    #include <sys/un.h>
    #include <sys/wait.h>
    #include <unistd.h>

    extern char **environ;
    static int sock = -1;

    /* The compiler's exit status once it ran, which a lost server connection must not replace. */
    static int32_t compiled = -1;

    /* `cargo __script <script> <arguments>`, as build-script shims start it, or `cargo __native <cc> <arguments>`, as
       the `cc` shim does, rather than `<rustc> <arguments>`. */
    enum { COMPILER, SCRIPT, NATIVE };
    static int mode = COMPILER;

    /* The Swift hook, or the compiler or script itself when there is none. */
    static void fallback(int argc, char **argv) {
        if (sock >= 0) close(sock);
        const char *tuist = getenv("TUIST_CARGO_HOOK_FALLBACK");
        if (!tuist || !*tuist) {
            if (mode != COMPILER) execv(argv[3], argv + 3); else execvp(argv[1], argv + 1);
            _exit(127);
        }
        char **arguments = calloc((size_t)argc + 3, sizeof(char *));
        if (!arguments) _exit(127);
        int count = 0;
        arguments[count++] = (char *)tuist;
        if (mode == COMPILER) { arguments[count++] = "cargo"; arguments[count++] = "__compiler"; }
        for (int i = 1; i < argc; i++) arguments[count++] = argv[i];
        execv(tuist, arguments);
        _exit(127);
    }

    static int write_all(int fd, const void *buffer, size_t count) {
        const char *bytes = buffer;
        while (count > 0) {
            ssize_t written = write(fd, bytes, count);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) return -1;
            bytes += written;
            count -= (size_t)written;
        }
        return 0;
    }

    static int read_all(int fd, void *buffer, size_t count) {
        char *bytes = buffer;
        while (count > 0) {
            ssize_t got = read(fd, bytes, count);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) return -1;
            bytes += got;
            count -= (size_t)got;
        }
        return 0;
    }

    static int send_frame(char tag, const void *payload, uint32_t length) {
        char header[5];
        header[0] = tag;
        memcpy(header + 1, &length, 4);
        if (write_all(sock, header, 5) != 0) return -1;
        return length ? write_all(sock, payload, length) : 0;
    }

    static int read_frame(char *tag, char **payload, uint32_t *length) {
        char header[5];
        if (read_all(sock, header, 5) != 0) return -1;
        *tag = header[0];
        memcpy(length, header + 1, 4);
        free(*payload);
        *payload = malloc((size_t)*length + 1);
        if (!*payload) return -1;
        if (*length && read_all(sock, *payload, *length) != 0) return -1;
        (*payload)[*length] = 0;
        return 0;
    }

    typedef struct { char *data; size_t length, capacity; } buffer_t;

    static void append(buffer_t *buffer, const char *bytes, size_t count) {
        if (buffer->length + count > buffer->capacity) {
            buffer->capacity = (buffer->length + count) * 2 + 4096;
            buffer->data = realloc(buffer->data, buffer->capacity);
            if (!buffer->data) _exit(127);
        }
        memcpy(buffer->data + buffer->length, bytes, count);
        buffer->length += count;
    }

    static void append_field(buffer_t *buffer, const char *field) { append(buffer, field, strlen(field) + 1); }

    static void append_count(buffer_t *buffer, size_t count) {
        char text[32];
        size_t i = sizeof(text);
        text[--i] = 0;
        do { text[--i] = (char)('0' + count % 10); count /= 10; } while (count && i);
        append_field(buffer, text + i);
    }

    /* Counted NUL-terminated fields starting at *cursor, as a NULL-terminated array. */
    static char **fields(char **cursor, char *end) {
        if (*cursor >= end) return NULL;
        long count = strtol(*cursor, NULL, 10);
        *cursor += strlen(*cursor) + 1;
        if (count < 0 || count > 1000000) return NULL;
        char **result = calloc((size_t)count + 1, sizeof(char *));
        if (!result) return NULL;
        for (long i = 0; i < count; i++) {
            if (*cursor >= end) return NULL;
            result[i] = *cursor;
            *cursor += strlen(*cursor) + 1;
        }
        return result;
    }

    static int run(char *payload, uint32_t length) {
        char *cursor = payload, *end = payload + length;
        char **arguments = fields(&cursor, end);
        char **environment = fields(&cursor, end);
        if (!arguments || !environment || !arguments[0]) return -1;
        int out[2], err[2];
        if (pipe(out) != 0 || pipe(err) != 0) return -1;
        fcntl(out[0], F_SETFD, FD_CLOEXEC);
        fcntl(err[0], F_SETFD, FD_CLOEXEC);
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, out[1], 1);
        posix_spawn_file_actions_adddup2(&actions, err[1], 2);
        posix_spawn_file_actions_addclose(&actions, out[1]);
        posix_spawn_file_actions_addclose(&actions, err[1]);
        pid_t pid;
        int spawned = posix_spawnp(&pid, arguments[0], &actions, NULL, arguments, environment);
        posix_spawn_file_actions_destroy(&actions);
        close(out[1]);
        close(err[1]);
        int32_t status = 127;
        if (spawned == 0) {
            struct pollfd pipes[2] = {{out[0], POLLIN, 0}, {err[0], POLLIN, 0}};
            int open_pipes = 2;
            char chunk[65536], tag = 0, *reply = NULL;
            uint32_t reply_length = 0;
            while (open_pipes > 0) {
                if (poll(pipes, 2, -1) < 0) { if (errno == EINTR) continue; break; }
                for (int i = 0; i < 2; i++) {
                    if (pipes[i].fd < 0 || !(pipes[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
                    ssize_t got = read(pipes[i].fd, chunk, sizeof(chunk));
                    if (got < 0 && errno == EINTR) continue;
                    if (got <= 0) { close(pipes[i].fd); pipes[i].fd = -1; open_pipes--; continue; }
                    if (i == 0) {
                        write_all(1, chunk, (size_t)got);
                        if (sock >= 0 && send_frame('o', chunk, (uint32_t)got) != 0) { close(sock); sock = -1; }
                    } else if (sock >= 0 && send_frame('e', chunk, (uint32_t)got) == 0
                               && read_frame(&tag, &reply, &reply_length) == 0 && tag == 'E') {
                        /* Forwarded only once the server has certified any metadata this announces. */
                        write_all(2, reply, reply_length);
                    } else {
                        if (sock >= 0) { close(sock); sock = -1; }
                        write_all(2, chunk, (size_t)got);
                    }
                }
            }
            free(reply);
            int raw = 0;
            while (waitpid(pid, &raw, 0) < 0 && errno == EINTR) {}
            status = WIFEXITED(raw) ? WEXITSTATUS(raw) : 128 + WTERMSIG(raw);
        }
        compiled = status;
        if (sock < 0 || send_frame('x', &status, 4) != 0) _exit(status);
        return 0;
    }

    int main(int argc, char **argv) {
        if (argc < 2) return 2;
        if (argc >= 4 && strcmp(argv[1], "cargo") == 0) {
            if (strcmp(argv[2], "__script") == 0) mode = SCRIPT;
            else if (strcmp(argv[2], "__native") == 0) mode = NATIVE;
        }
        int first = mode == COMPILER ? 1 : 3;
        /* Cargo passes loader variables such as DYLD_FALLBACK_LIBRARY_PATH. The shell wrapper this replaces never
           forwarded them (SIP removes them when /bin/sh starts), and caching bypasses compilations that carry them. */
        for (int found = 1; found;) {
            found = 0;
            for (char **entry = environ; *entry; entry++) {
                if (strncmp(*entry, "DYLD_", 5) != 0) continue;
                char name[256];
                size_t length = strcspn(*entry, "=");
                if (length >= sizeof(name)) continue;
                memcpy(name, *entry, length);
                name[length] = 0;
                unsetenv(name);
                found = 1;
                break;
            }
        }
        const char *path = getenv("TUIST_CARGO_HOOK_SOCKET");
        struct sockaddr_un address;
        if (!path || strlen(path) >= sizeof(address.sun_path)) fallback(argc, argv);
        sock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sock < 0) fallback(argc, argv);
        fcntl(sock, F_SETFD, FD_CLOEXEC);
        int on = 1;
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        memset(&address, 0, sizeof(address));
        address.sun_family = AF_UNIX;
        strcpy(address.sun_path, path);
        if (connect(sock, (struct sockaddr *)&address, sizeof(address)) != 0) fallback(argc, argv);
        buffer_t request = {0};
        char directory[4096];
        if (!getcwd(directory, sizeof(directory))) fallback(argc, argv);
        append_field(&request, directory);
        append_count(&request, (size_t)(argc - first));
        for (int i = first; i < argc; i++) append_field(&request, argv[i]);
        size_t variables = 0;
        for (char **entry = environ; *entry; entry++) variables++;
        append_count(&request, variables);
        for (char **entry = environ; *entry; entry++) append_field(&request, *entry);
        char kind = mode == SCRIPT ? 'S' : mode == NATIVE ? 'N' : 'Q';
        if (send_frame(kind, request.data, (uint32_t)request.length) != 0) fallback(argc, argv);
        int started = 0;
        char tag, *payload = NULL;
        uint32_t length = 0;
        for (;;) {
            if (read_frame(&tag, &payload, &length) != 0) {
                /* The server went away: before rustc ran, run the Swift hook; after, report how rustc exited. */
                if (!started || compiled < 0) fallback(argc, argv);
                return compiled;
            }
            switch (tag) {
            case 'O': write_all(1, payload, length); break;
            case 'E': write_all(2, payload, length); break;
            case 'X': { int32_t code = 1; if (length == 4) memcpy(&code, payload, 4); return code; }
            case 'R': started = 1; if (run(payload, length) != 0) fallback(argc, argv); break;
            default: fallback(argc, argv);
            }
        }
    }
    """#
}
