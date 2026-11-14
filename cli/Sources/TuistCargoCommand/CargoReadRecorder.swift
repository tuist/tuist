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
enum CargoReadRecorder { // swiftlint:disable:this type_body_length
    static let version = "tuist-cargo-recorder-v2"

    /// Universal: macOS strips `DYLD_*` from its arm64e system programs (`/bin/sh`, `/usr/bin/cc`) only while System
    /// Integrity Protection is on. With it off, as on many CI machines, they load the recorder too (which then stands
    /// down in them), and dyld terminates a process whose inserted library has no slice for it.
    static let compilerArguments = ["-dynamiclib", "-O2", "-arch", "arm64", "-arch", "arm64e"]

    /// Builds the recorder once per cache directory with the system C compiler. `nil` when unsupported or unavailable.
    /// How it is compiled names the file, not `version`, which keys recorded runs: their reads do not depend on it.
    static func prepare(cacheDirectory: URL) -> URL? {
        #if os(macOS) && arch(arm64)
            let identity = SHA256.hash(data: Data((version + compilerArguments.joined(separator: " ") + source).utf8))
                .map { String(format: "%02x", $0) }.joined()
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
                process.arguments = ["clang"] + compilerArguments + ["-o", output.path, file.path]
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

    /// The log of the build-script run being recorded, so the `cc` its compilers start through the `/bin/sh` shim joins
    /// it; a recorded compilation inside the script has a log of its own.
    static let scriptLogVariable = "TUIST_CARGO_READ_SCRIPT"

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
    static char **initial_environment = NULL;
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
        char executable[MAXPATHLEN];
        uint32_t size = sizeof executable;
        int located = _NSGetExecutablePath(executable, &size) == 0;
        /* System Integrity Protection strips `DYLD_*` from protected programs (`/bin/sh`, `/usr/bin/cc`, `xcrun`),
           whose files carry the restricted flag, so they never load this library. With it off they do: such a process
           records nothing and drops `DYLD_*` as SIP would, so runs are recorded the same way on every machine. */
        struct stat status;
        if (located && stat(executable, &status) == 0 && (status.st_flags & SF_RESTRICTED)) {
            char **current = *_NSGetEnviron();
            size_t count = 0;
            while (current != NULL && current[count] != NULL) count++;
            char **names = calloc(count + 1, sizeof(char *));
            size_t found = 0;
            for (size_t index = 0; names != NULL && index < count; index++) {
                const char *equals = strchr(current[index], '=');
                if (strncmp(current[index], "DYLD_", 5) == 0 && equals != NULL) {
                    names[found++] = strndup(current[index], (size_t)(equals - current[index]));
                }
            }
            for (size_t index = 0; index < found; index++) { unsetenv(names[index]); free(names[index]); }
            free(names);
            depth--;
            return;
        }
        const char *log = getenv("TUIST_CARGO_READ_LOG");
        if (log != NULL) log_fd = open(log, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
        const char *root = getenv("TUIST_CARGO_READ_TOOLCHAIN");
        if (root != NULL) strlcpy(toolchain, root, sizeof toolchain);
        emit('P', located ? executable : "?");
        /* The environment the process started with, which the key holds: a query's own is logged against it. */
        char **current = *_NSGetEnviron();
        size_t count = 0;
        while (current != NULL && current[count] != NULL) count++;
        initial_environment = calloc(count + 1, sizeof(char *));
        for (size_t index = 0; initial_environment != NULL && index < count; index++) {
            initial_environment[index] = strdup(current[index]);
        }
        char parent[32];
        snprintf(parent, sizeof parent, "%d", getppid());
        emit('p', parent);
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

    /* Queries such as `git describe` and tools such as `codesign` run from protected programs the recorder cannot
       load into. A spawn of one is logged with the program that ran, its working directory, how its environment
       differs from the one this process started with (`NAME=VALUE` set, `-NAME` removed) and its arguments (`Q`),
       so the key can hold what a query prints, re-run at lookup in the same environment, or what a tool reads,
       instead of their reads. Neither may start in a directory the spawn changes. */
    static pthread_mutex_t query_lock = PTHREAD_MUTEX_INITIALIZER;
    static const void *chdir_actions[64];
    static int queries_unknown = 0;

    static void mark_chdir(const void *actions, int changes) {
        pthread_mutex_lock(&query_lock);
        int stored = !changes;
        for (int index = 0; index < 64; index++) {
            if (chdir_actions[index] == actions) { chdir_actions[index] = changes ? actions : NULL; stored = 1; break; }
        }
        for (int index = 0; index < 64 && !stored; index++) {
            if (chdir_actions[index] == NULL) { chdir_actions[index] = actions; stored = 1; }
        }
        if (!stored) queries_unknown = 1;
        pthread_mutex_unlock(&query_lock);
    }

    static int changes_directory(const void *actions) {
        if (actions == NULL) return 0;
        pthread_mutex_lock(&query_lock);
        int found = 0;
        for (int index = 0; index < 64; index++) if (chdir_actions[index] == actions) found = 1;
        pthread_mutex_unlock(&query_lock);
        return found;
    }

    static int my_addchdir(posix_spawn_file_actions_t *actions, const char *path) {
        mark_chdir(actions, 1);
        return posix_spawn_file_actions_addchdir_np(actions, path);
    }
    INTERPOSE(my_addchdir, posix_spawn_file_actions_addchdir_np)
    static int my_addfchdir(posix_spawn_file_actions_t *actions, int directory) {
        mark_chdir(actions, 1);
        return posix_spawn_file_actions_addfchdir_np(actions, directory);
    }
    INTERPOSE(my_addfchdir, posix_spawn_file_actions_addfchdir_np)
    #if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    static int my_addchdir_posix(posix_spawn_file_actions_t *actions, const char *path) {
        mark_chdir(actions, 1);
        return posix_spawn_file_actions_addchdir(actions, path);
    }
    INTERPOSE(my_addchdir_posix, posix_spawn_file_actions_addchdir)
    static int my_addfchdir_posix(posix_spawn_file_actions_t *actions, int directory) {
        mark_chdir(actions, 1);
        return posix_spawn_file_actions_addfchdir(actions, directory);
    }
    INTERPOSE(my_addfchdir_posix, posix_spawn_file_actions_addfchdir)
    #endif
    static int my_actions_destroy(posix_spawn_file_actions_t *actions) {
        mark_chdir(actions, 0);
        return posix_spawn_file_actions_destroy(actions);
    }
    INTERPOSE(my_actions_destroy, posix_spawn_file_actions_destroy)

    static int representable(const char *text) {
        return text != NULL && strpbrk(text, "\n\t\x1e\x1f") == NULL;
    }

    static size_t name_length(const char *entry) {
        const char *equals = strchr(entry, '=');
        return equals == NULL ? strlen(entry) : (size_t)(equals - entry);
    }

    /* Appends how `environment` differs from the initial one, entries separated by `\x1e`. -1 when it cannot. */
    static int append_environment(char *line, size_t size, int length, char *const environment[]) {
        if (initial_environment == NULL) return -1;
        int first = 1;
        for (int index = 0; environment != NULL && environment[index] != NULL; index++) {
            int same = 0;
            for (int other = 0; initial_environment[other] != NULL && !same; other++) {
                same = strcmp(environment[index], initial_environment[other]) == 0;
            }
            if (same) continue;
            if (!representable(environment[index])) return -1;
            length += snprintf(line + length, size - (size_t)length, "%s%s", first ? "" : "\x1e", environment[index]);
            first = 0;
            if (length <= 0 || (size_t)length >= size) return -1;
        }
        for (int other = 0; initial_environment[other] != NULL; other++) {
            size_t name = name_length(initial_environment[other]);
            int kept = 0;
            for (int index = 0; environment != NULL && environment[index] != NULL && !kept; index++) {
                kept = name_length(environment[index]) == name && strncmp(environment[index], initial_environment[other], name) == 0;
            }
            if (kept) continue;
            if (!representable(initial_environment[other])) return -1;
            length += snprintf(line + length, size - (size_t)length, "%s-%.*s", first ? "" : "\x1e", (int)name,
                               initial_environment[other]);
            first = 0;
            if (length <= 0 || (size_t)length >= size) return -1;
        }
        return length;
    }

    static int is_modeled(const char *path) {
        const char *name = strrchr(path, '/');
        name = name == NULL ? path : name + 1;
        const char *programs[] = { "git", "sw_vers", "uname", "xcode-select", "xcrun", "codesign", "swiftc", "ar", "ranlib" };
        for (size_t index = 0; index < sizeof programs / sizeof *programs; index++) {
            if (strcmp(name, programs[index]) == 0) return 1;
        }
        return 0;
    }

    /* `searched`: `path` is a name to find in `PATH`, as `posix_spawnp` does; otherwise the program that runs. */
    static int log_query(char kind, const char *path, int searched, const posix_spawn_file_actions_t *actions,
                         char *const arguments[], char *const environment[]) {
        if (!is_modeled(path) || changes_directory(actions)) return 0;
        char directory[MAXPATHLEN];
        if (getcwd(directory, sizeof directory) == NULL || !representable(directory)) return 0;
        /* The program as `posix_spawnp` found it: the key names what ran, not what a PATH elsewhere would find. */
        char resolved[MAXPATHLEN];
        if (!searched || strchr(path, '/') != NULL) {
            if (path[0] == '/') strlcpy(resolved, path, sizeof resolved);
            else snprintf(resolved, sizeof resolved, "%s/%s", directory, path);
        } else {
            const char *search = getenv("PATH");
            if (search == NULL) search = "/usr/bin:/bin:/usr/sbin:/sbin";
            resolved[0] = 0;
            while (resolved[0] == 0 && search != NULL) {
                const char *end = strchr(search, ':');
                size_t length = end == NULL ? strlen(search) : (size_t)(end - search);
                char candidate[MAXPATHLEN];
                if (length == 0) snprintf(candidate, sizeof candidate, "%s/%s", directory, path);
                else if (search[0] == '/') snprintf(candidate, sizeof candidate, "%.*s/%s", (int)length, search, path);
                else snprintf(candidate, sizeof candidate, "%s/%.*s/%s", directory, (int)length, search, path);
                struct stat value;
                if (stat(candidate, &value) == 0 && S_ISREG(value.st_mode) && access(candidate, X_OK) == 0) {
                    strlcpy(resolved, candidate, sizeof resolved);
                }
                search = end == NULL ? NULL : end + 1;
            }
            if (resolved[0] == 0) return 0;
        }
        if (!representable(resolved)) return 0;
        char line[16384];
        int length = snprintf(line, sizeof line, "%d\t%c\t%s\x1f%s\x1f", getpid(), kind, resolved, directory);
        if (length <= 0 || (size_t)length >= sizeof line) return 0;
        length = append_environment(line, sizeof line, length, environment);
        if (length < 0) return 0;
        for (int index = 0; arguments != NULL && arguments[index] != NULL; index++) {
            if (length <= 0 || (size_t)length >= sizeof line || !representable(arguments[index])) return 0;
            length += snprintf(line + length, sizeof line - (size_t)length, "\x1f%s", arguments[index]);
        }
        if (length <= 0 || (size_t)length + 1 >= sizeof line) return 0;
        line[length++] = '\n';
        write(log_fd, line, (size_t)length);
        if (environment == *_NSGetEnviron()) emit('x', "*");
        return 1;
    }

    static int queried(const char *path, const posix_spawn_file_actions_t *actions, char *const arguments[],
                       char *const environment[]) {
        if (!ready || depth != 0 || log_fd < 0 || queries_unknown) return 0;
        depth++;
        int logged = log_query('Q', path, 1, actions, arguments, environment);
        depth--;
        return logged;
    }

    /* A successful exec does not return, so it is logged before; `Y` withdraws an attempt that failed, such as
       each PATH directory `execvp` tries before the one that holds the program. */
    /* A modeled program is logged as a query (`J`, withdrawn by `Z`), as a forked child running `execvp` does. */
    static int my_execve(const char *path, char *const arguments[], char *const environment[]) {
        int logged = ready && depth == 0, query = 0;
        if (logged && log_fd >= 0 && !queries_unknown) {
            depth++;
            query = log_query('J', path, 0, NULL, arguments, environment);
            depth--;
        }
        if (!query) spawned(path, environment);
        int result = execve(path, arguments, environment);
        if (logged) { int saved = errno; depth++; emit(query ? 'Z' : 'Y', path); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_execve, execve)

    /* `POSIX_SPAWN_SETEXEC` replaces this process like `execve`, so a successful one does not return either. */
    static int replaces_process(const posix_spawnattr_t *attributes) {
        short flags = 0;
        return attributes != NULL && posix_spawnattr_getflags(attributes, &flags) == 0 && (flags & POSIX_SPAWN_SETEXEC);
    }

    /* Spawns are logged once they succeed, and the real call runs with the guard held: `posix_spawnp` searches
       PATH through `posix_spawn`, whose attempts are not separate spawns. One that replaces the process is logged
       before, and withdrawn when it fails. */
    static int my_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        int logged = ready && depth == 0, replaces = logged && replaces_process(attributes);
        if (replaces) spawned(path, environment);
        depth++;
        int result = posix_spawn(pid, path, actions, attributes, arguments, environment);
        depth--;
        if (replaces && result != 0) { depth++; emit('Y', path); depth--; }
        if (logged && !replaces && result == 0 && !queried(path, actions, arguments, environment)) spawned(path, environment);
        return result;
    }
    INTERPOSE(my_posix_spawn, posix_spawn)

    static int my_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        int logged = ready && depth == 0, replaces = logged && replaces_process(attributes);
        if (replaces) spawned(file, environment);
        depth++;
        int result = posix_spawnp(pid, file, actions, attributes, arguments, environment);
        depth--;
        if (replaces && result != 0) { depth++; emit('Y', file); depth--; }
        if (logged && !replaces && result == 0 && !queried(file, actions, arguments, environment)) spawned(file, environment);
        return result;
    }
    INTERPOSE(my_posix_spawnp, posix_spawnp)

    static int my_connect(int socket, const struct sockaddr *address, socklen_t length) {
        if (ready && depth == 0) { depth++; emit('N', "connect"); depth--; }
        return connect(socket, address, length);
    }
    INTERPOSE(my_connect, connect)
    """#
}
