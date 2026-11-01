import Crypto
import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#endif

/// Records what a compiler or build script actually reads, as blaze's sandbox does, so its cache key can name those
/// inputs instead of rejecting code whose reads the key cannot predict (proc macros, `asm!` includes, bundled native
/// libraries, build scripts). A small library injected with `DYLD_INSERT_LIBRARIES` interposes libc's file, directory,
/// environment, process and network entry points and appends one line per event to `TUIST_CARGO_READ_LOG`.
///
/// It observes, it does not enforce: anything it cannot see makes the run uncacheable rather than unsound. A child
/// process that does not load the recorder (macOS strips `DYLD_*` from protected programs such as `/bin/sh` or
/// `/usr/bin/cc`), a network connection, or an unparsable log all mean the run is not published.
enum CargoReadRecorder {
    static let version = "tuist-cargo-recorder-v1"

    /// Builds the recorder once per cache directory with the system C compiler. `nil` when unsupported or unavailable.
    static func prepare(cacheDirectory: URL) -> URL? {
        #if os(macOS) && arch(arm64)
            let identity = SHA256.hash(data: Data((version + source).utf8)).map { String(format: "%02x", $0) }.joined()
            let directory = cacheDirectory.appendingPathComponent("recorder")
            let library = directory.appendingPathComponent("\(identity.prefix(16)).dylib")
            if FileManager.default.isExecutableFile(atPath: library.path) { return library }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let lock = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
                guard lock >= 0 else { return nil }
                defer { close(lock) }
                _ = flock(lock, LOCK_EX)
                if FileManager.default.isExecutableFile(atPath: library.path) { return library }
                let staging = directory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                let file = staging.appendingPathComponent("recorder.c")
                try Data(source.utf8).write(to: file)
                let output = staging.appendingPathComponent("recorder.dylib")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["clang", "-dynamiclib", "-O2", "-arch", "arm64", "-o", output.path, file.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                try FileManager.default.moveItem(at: output, to: library)
                return library
            } catch { return nil }
        #else
            return nil
        #endif
    }

    /// The environment a recorded run starts with.
    static func environment(
        _ environment: [String: String], library: String, log: URL, toolchain: String
    ) -> [String: String] {
        var result = environment
        result["DYLD_INSERT_LIBRARIES"] = library
        result["TUIST_CARGO_READ_LOG"] = log.path
        result["TUIST_CARGO_READ_TOOLCHAIN"] = toolchain
        return result
    }

    static let source = #"""
    #include <dirent.h>
    #include <dlfcn.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <spawn.h>
    #include <stdarg.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/param.h>
    #include <sys/socket.h>
    #include <sys/stat.h>
    #include <unistd.h>
    #include <pthread.h>
    #include <crt_externs.h>
    #include <mach-o/dyld.h>

    #define INTERPOSE(replacement, replacee) \
        __attribute__((used)) static struct { const void *a; const void *b; } interpose_##replacee \
        __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&replacee };

    static int log_fd = -1;
    static int ready = 0;
    static char toolchain[MAXPATHLEN];
    /* Thread-local storage is unavailable to interposing libraries, so the reentrancy count lives in a pthread key. */
    static pthread_key_t depth_key;
    static int *depth_slot(void) {
        int *slot = pthread_getspecific(depth_key);
        if (slot == NULL) { slot = calloc(1, sizeof(int)); pthread_setspecific(depth_key, slot); }
        return slot;
    }
    #define depth (*depth_slot())

    static void emit(char kind, const char *text) {
        if (log_fd < 0 || text == NULL) return;
        char line[MAXPATHLEN * 2 + 64];
        int length = snprintf(line, sizeof line, "%d\t%c\t%s\n", getpid(), kind, text);
        if (length <= 0) return;
        if ((size_t)length >= sizeof line || strchr(text, '\n') != NULL) {
            length = snprintf(line, sizeof line, "%d\t?\tunrepresentable\n", getpid());
        }
        write(log_fd, line, (size_t)length);
    }

    static void emit_path(char kind, int directory, const char *path) {
        if (path == NULL) return;
        char absolute[MAXPATHLEN * 2];
        if (path[0] == '/') {
            emit(kind, path);
            return;
        }
        char base[MAXPATHLEN];
        if (directory == AT_FDCWD) {
            if (getcwd(base, sizeof base) == NULL) { emit('?', "cwd"); return; }
        } else if (fcntl(directory, F_GETPATH, base) == -1) {
            emit('?', "dirfd");
            return;
        }
        snprintf(absolute, sizeof absolute, "%s/%s", base, path);
        emit(kind, absolute);
    }

    __attribute__((constructor)) static void start(void) {
        if (pthread_key_create(&depth_key, free) != 0) return;
        depth++;
        const char *log = getenv("TUIST_CARGO_READ_LOG");
        if (log != NULL) log_fd = open(log, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
        const char *root = getenv("TUIST_CARGO_READ_TOOLCHAIN");
        if (root != NULL) strlcpy(toolchain, root, sizeof toolchain);
        char executable[MAXPATHLEN];
        uint32_t size = sizeof executable;
        emit('P', _NSGetExecutablePath(executable, &size) == 0 ? executable : "?");
        ready = 1;
        depth--;
    }

    /* Whether the calling code is the toolchain's or the system's, whose own environment reads are not the crate's. */
    static int from_toolchain(const void *caller) {
        Dl_info info;
        if (!ready || dladdr(caller, &info) == 0 || info.dli_fname == NULL) return 1;
        if (strncmp(info.dli_fname, "/usr/lib/", 9) == 0 || strncmp(info.dli_fname, "/System/", 8) == 0) return 1;
        size_t length = strlen(toolchain);
        return length > 0 && strncmp(info.dli_fname, toolchain, length) == 0;
    }

    static void opened(int directory, const char *path, int flags, int result) {
        if (result >= 0) {
            struct stat value;
            if (fstat(result, &value) == 0 && S_ISDIR(value.st_mode)) return;
            emit_path((flags & (O_WRONLY | O_RDWR | O_CREAT | O_TRUNC)) ? 'W' : 'R', directory, path);
        } else if (errno == ENOENT || errno == ENOTDIR) {
            emit_path('A', directory, path);
        }
    }

    static int my_open(const char *path, int flags, ...) {
        int mode = 0;
        if (flags & O_CREAT) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
        int result = open(path, flags, mode);
        if (ready && depth == 0) { int saved = errno; depth++; opened(AT_FDCWD, path, flags, result); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_open, open)

    static int my_openat(int directory, const char *path, int flags, ...) {
        int mode = 0;
        if (flags & O_CREAT) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
        int result = openat(directory, path, flags, mode);
        if (ready && depth == 0) { int saved = errno; depth++; opened(directory, path, flags, result); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_openat, openat)

    static void looked_up(int directory, const char *path, int result) {
        if (!ready || depth != 0) return;
        int saved = errno;
        depth++;
        if (result == 0) emit_path('S', directory, path);
        else if (saved == ENOENT || saved == ENOTDIR) emit_path('A', directory, path);
        depth--;
        errno = saved;
    }

    static int my_stat(const char *path, struct stat *value) { int r = stat(path, value); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_stat, stat)
    static int my_lstat(const char *path, struct stat *value) { int r = lstat(path, value); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_lstat, lstat)
    static int my_fstatat(int directory, const char *path, struct stat *value, int flags) {
        int r = fstatat(directory, path, value, flags);
        looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_fstatat, fstatat)
    static int my_access(const char *path, int mode) { int r = access(path, mode); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_access, access)
    static ssize_t my_readlink(const char *path, char *buffer, size_t size) {
        ssize_t r = readlink(path, buffer, size);
        looked_up(AT_FDCWD, path, r >= 0 ? 0 : -1);
        return r;
    }
    INTERPOSE(my_readlink, readlink)

    static DIR *my_opendir(const char *path) {
        DIR *result = opendir(path);
        if (ready && depth == 0) {
            int saved = errno;
            depth++;
            if (result != NULL) emit_path('D', AT_FDCWD, path);
            else if (saved == ENOENT || saved == ENOTDIR) emit_path('A', AT_FDCWD, path);
            depth--;
            errno = saved;
        }
        return result;
    }
    INTERPOSE(my_opendir, opendir)

    static char *my_getenv(const char *name) {
        char *result = getenv(name);
        if (ready && depth == 0 && name != NULL && !from_toolchain(__builtin_return_address(0))) {
            depth++;
            emit('E', name);
            depth--;
        }
        return result;
    }
    INTERPOSE(my_getenv, getenv)

    /* Reading the whole environment. A spawn that hands the same environment to a child is pass-through, not a read. */
    static char ***my_NSGetEnviron(void) {
        char ***result = _NSGetEnviron();
        if (ready && depth == 0 && !from_toolchain(__builtin_return_address(0))) {
            depth++;
            emit('e', "*");
            depth--;
        }
        return result;
    }
    INTERPOSE(my_NSGetEnviron, _NSGetEnviron)

    static void spawned(const char *path, char *const environment[]) {
        if (!ready || depth != 0) return;
        depth++;
        emit('X', path);
        if (environment == *_NSGetEnviron()) emit('x', "*");
        depth--;
    }

    static int my_execve(const char *path, char *const arguments[], char *const environment[]) {
        spawned(path, environment);
        return execve(path, arguments, environment);
    }
    INTERPOSE(my_execve, execve)

    static int my_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        spawned(path, environment);
        return posix_spawn(pid, path, actions, attributes, arguments, environment);
    }
    INTERPOSE(my_posix_spawn, posix_spawn)

    static int my_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        spawned(file, environment);
        return posix_spawnp(pid, file, actions, attributes, arguments, environment);
    }
    INTERPOSE(my_posix_spawnp, posix_spawnp)

    static int my_connect(int socket, const struct sockaddr *address, socklen_t length) {
        if (ready && depth == 0) { depth++; emit('N', "connect"); depth--; }
        return connect(socket, address, length);
    }
    INTERPOSE(my_connect, connect)
    """#
}
