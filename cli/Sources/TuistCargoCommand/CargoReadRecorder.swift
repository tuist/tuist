import Crypto
import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#endif

/// Records what a compiler or build script actually reads, as blaze's sandbox does, so its cache key can name those
/// inputs instead of rejecting code whose reads the key cannot predict (proc macros, `asm!` includes, bundled native
/// libraries, build scripts). A small library injected with `DYLD_INSERT_LIBRARIES` on macOS and `LD_PRELOAD` on Linux
/// interposes libc's file, directory, environment, process and network entry points and appends one line per event to
/// `TUIST_CARGO_READ_LOG`.
///
/// It observes, it does not enforce: anything it cannot see makes the run uncacheable rather than unsound. A child
/// process that does not load the recorder (macOS strips `DYLD_*` from protected programs such as `/bin/sh` or
/// `/usr/bin/cc`; a statically linked Linux program has no loader), a network connection, or an unparsable log all mean
/// the run is not published.
enum CargoReadRecorder { // swiftlint:disable:this type_body_length
    static let version = "tuist-cargo-recorder-v2"

    #if os(macOS)
        /// Universal: macOS strips `DYLD_*` from its arm64e system programs (`/bin/sh`, `/usr/bin/cc`) only while System
        /// Integrity Protection is on. With it off, as on many CI machines, they load the recorder too (which then stands
        /// down in them), and dyld terminates a process whose inserted library has no slice for it.
        static let compilerArguments = ["-dynamiclib", "-O2", "-arch", "arm64", "-arch", "arm64e"]
        static let libraryExtension = "dylib"
        static let loaderVariable = "DYLD_INSERT_LIBRARIES"
        /// Programs whose spawns are logged as queries or tools (`CargoQuery`, `CargoTool`), whose own events are not
        /// the run's.
        static let modeledPrograms = CargoQuery.programs.union(CargoTool.programs)
    #else
        /// Linked against glibc's `dlsym` and pthreads explicitly, which glibc before 2.34 keeps in separate libraries.
        static let compilerArguments = ["-shared", "-fPIC", "-O2"]
        static let linkArguments = ["-ldl", "-lpthread"]
        static let libraryExtension = "so"
        static let loaderVariable = "LD_PRELOAD"
        /// Every program but these queries loads the recorder and is recorded like the run itself, the archivers among
        /// them.
        static let modeledPrograms = CargoQuery.programs
    #endif

    /// Builds the recorder once per cache directory with the system C compiler (`xcrun clang` on macOS, `cc` from
    /// `PATH` on Linux, which Rust needs there to link). `nil` when unsupported or unavailable. How it is compiled names
    /// the file, not `version`, which keys recorded runs: their reads do not depend on it.
    static func prepare(cacheDirectory: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if (os(macOS) && arch(arm64)) || (os(Linux) && (arch(x86_64) || arch(arm64)))
            #if os(macOS)
                let compiler = ["/usr/bin/xcrun", "clang"]
                let linkArguments: [String] = []
                let platform = ""
            #else
                guard let cc = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":")
                    .map({ String($0) + "/cc" })
                    .first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) })
                else { return nil }
                let compiler = [cc]
                /// The C library and architecture it was built for, which decide the entry points it wraps, and the
                /// compiler that built it, so a cache directory shared between machines or kept across a system
                /// upgrade does not reuse a library built for another.
                var libc = [CChar](repeating: 0, count: 64)
                _ = confstr(Int32(_CS_GNU_LIBC_VERSION), &libc, libc.count)
                #if arch(x86_64)
                    let architecture = "x86_64"
                #else
                    let architecture = "arm64"
                #endif
                let platform = [String(cString: libc), architecture, cc].joined(separator: " ")
            #endif
            let identity = SHA256.hash(
                data: Data((version + platform + (compilerArguments + linkArguments).joined(separator: " ") + source).utf8)
            ).map { String(format: "%02x", $0) }.joined()
            let directory = cacheDirectory.appendingPathComponent("recorder")
            let library = directory.appendingPathComponent("\(identity.prefix(16)).\(libraryExtension)")
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
                let output = staging.appendingPathComponent("recorder.\(libraryExtension)")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: compiler[0])
                process.arguments = Array(compiler.dropFirst()) + compilerArguments + ["-o", output.path, file.path]
                    + linkArguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                #if os(Linux)
                    // The loader only warns about a preloaded library it cannot load, on stderr, which belongs to rustc's
                    // messages: one that does not load into the shell and record it is never installed.
                    let log = staging.appendingPathComponent("check.log")
                    let errors = staging.appendingPathComponent("check.err")
                    FileManager.default.createFile(atPath: errors.path, contents: nil)
                    let check = Process()
                    check.executableURL = URL(fileURLWithPath: "/bin/sh")
                    check.arguments = ["-c", ":"]
                    check.environment = ["PATH": "/usr/bin:/bin", loaderVariable: output.path, "TUIST_CARGO_READ_LOG": log.path]
                    check.standardOutput = FileHandle.nullDevice
                    check.standardError = try FileHandle(forWritingTo: errors)
                    try check.run()
                    check.waitUntilExit()
                    guard check.terminationStatus == 0, (try? Data(contentsOf: errors))?.isEmpty == true,
                          (try? String(contentsOf: log, encoding: .utf8))?.contains("\tP\t") == true
                    else { return nil }
                #endif
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
        result[loaderVariable] = library
        result["TUIST_CARGO_READ_LOG"] = log.path
        result["TUIST_CARGO_READ_TOOLCHAIN"] = toolchain
        return result
    }

    static let source = #"""
    #if defined(__linux__)
    #define _GNU_SOURCE
    #undef _FORTIFY_SOURCE
    #endif
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
    #include <sys/un.h>
    #include <sys/stat.h>
    #include <unistd.h>
    #include <pthread.h>
    #if defined(__APPLE__)
    #include <crt_externs.h>
    #include <mach-o/dyld.h>

    #define INTERPOSE(replacement, replacee) \
        __attribute__((used)) static struct { const void *a; const void *b; } interpose_##replacee \
        __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&replacee };
    /* dyld's interposing leaves this library's own calls alone, so they reach the real functions. */
    #define REAL_DECLARE(name)
    #define REAL(name) name
    #define ENVIRON (*_NSGetEnviron())
    #define TAKES_MODE O_CREAT
    #define GLIBC_AT_LEAST(major, minor) 1
    #else
    #if !defined(__GLIBC__)
    #error "The read recorder interposes glibc"
    #endif
    /* Before 2.33 `stat` and its relatives are inline wrappers in the headers rather than functions this library can
       define and reach. */
    #if !__GLIBC_PREREQ(2, 33)
    #error "The read recorder needs glibc 2.33 or later"
    #endif
    #include <alloca.h>
    #include <fts.h>
    #include <ftw.h>
    #include <glob.h>
    #include <link.h>
    #include <sys/syscall.h>
    #include <wordexp.h>

    extern char **environ;
    /* `LD_PRELOAD` interposes by symbol name: this library defines the functions it records under their own names, and
       reaches the definitions the program would otherwise have called, glibc's, as the next ones in the search order.
       Since glibc 2.33 some (`__xstat64`) exist only in their original version, which programs linked against older
       glibc, rustc among them, still call, and plain `dlsym` does not return. */
    static void *resolve(const char *name) {
        void *found = dlsym(RTLD_NEXT, name);
        const char *versions[] = { "GLIBC_2.2.5", "GLIBC_2.4", "GLIBC_2.17", "GLIBC_2.0", "GLIBC_2.1", "GLIBC_2.3" };
        for (size_t index = 0; found == NULL && index < sizeof versions / sizeof *versions; index++) {
            found = dlvsym(RTLD_NEXT, name, versions[index]);
        }
        return found;
    }
    #define REAL_DECLARE(name) static __typeof__(name) *real_##name;
    #define REAL(name) ({ if (real_##name == NULL) real_##name = (__typeof__(name) *)resolve(#name); real_##name; })
    #define INTERPOSE(replacement, replacee) \
        extern __typeof__(replacee) replacee __attribute__((alias(#replacement), visibility("default")));
    #define ENVIRON environ
    #define TAKES_MODE (O_CREAT | O_TMPFILE)
    #define GLIBC_AT_LEAST(major, minor) __GLIBC_PREREQ(major, minor)
    #define strlcpy(destination, source, size) ((size_t)snprintf((destination), (size), "%s", (source)))
    /* Removed from glibc's headers in 2.33, still exported for programs linked against older glibc. */
    extern int __xstat(int, const char *, struct stat *);
    extern int __lxstat(int, const char *, struct stat *);
    extern int __fxstatat(int, int, const char *, struct stat *, int);
    extern int __xstat64(int, const char *, struct stat64 *);
    extern int __lxstat64(int, const char *, struct stat64 *);
    extern int __fxstatat64(int, int, const char *, struct stat64 *, int);
    extern int __open_2(const char *, int);
    extern int __open64_2(const char *, int);
    extern int __openat_2(int, const char *, int);
    extern int __openat64_2(int, const char *, int);
    /* The fortified variants `_FORTIFY_SOURCE` builds call, declared only when it is on. */
    extern char *__realpath_chk(const char *, char *, size_t);
    extern ssize_t __readlink_chk(const char *, char *, size_t, size_t);
    extern ssize_t __readlinkat_chk(int, const char *, char *, size_t, size_t);
    extern int __open(const char *, int, ...);
    extern int __open64(const char *, int, ...);
    #endif

    static int log_fd = -1;
    static char **initial_environment = NULL;
    static int ready = 0;
    static char toolchain[MAXPATHLEN];
    #if defined(__APPLE__)
    /* Thread-local storage is unavailable to interposing libraries, so the reentrancy count lives in a pthread key. */
    static pthread_key_t depth_key;
    static int *depth_slot(void) {
        int *slot = pthread_getspecific(depth_key);
        if (slot == NULL) { slot = calloc(1, sizeof(int)); pthread_setspecific(depth_key, slot); }
        return slot;
    }
    #define depth (*depth_slot())
    #define START_DEPTH() (pthread_key_create(&depth_key, free) == 0)
    #else
    /* Static thread-local storage, which never allocates: rustc's jemalloc reads its settings through `secure_getenv`
       while it initializes, and allocating the count there would deadlock it. The library is preloaded, never opened
       later, so its variables fit the initial block, whose accesses never call into the loader. */
    static __thread int depth __attribute__((tls_model("initial-exec")));
    #define START_DEPTH() 1
    #endif

    REAL_DECLARE(open)
    REAL_DECLARE(openat)
    REAL_DECLARE(stat)
    REAL_DECLARE(lstat)
    REAL_DECLARE(fstatat)
    REAL_DECLARE(access)
    REAL_DECLARE(readlink)
    REAL_DECLARE(opendir)
    REAL_DECLARE(getenv)
    REAL_DECLARE(execve)
    REAL_DECLARE(posix_spawn)
    REAL_DECLARE(posix_spawnp)
    #if GLIBC_AT_LEAST(2, 29)
    REAL_DECLARE(posix_spawn_file_actions_addchdir_np)
    REAL_DECLARE(posix_spawn_file_actions_addfchdir_np)
    #endif
    REAL_DECLARE(posix_spawn_file_actions_destroy)
    REAL_DECLARE(connect)
    REAL_DECLARE(_exit)
    REAL_DECLARE(_Exit)

    /* Events are buffered per process and written in batches rather than with one `write` each, which rustc and
       clang make for every header and source they look up. The buffer is written before this process starts or
       becomes another program, so a child's events follow its parent's, and when it exits, with an `F` event the
       parser requires: a process that loaded the recorder and died before writing its events makes the run
       uncacheable rather than leave its reads out. */
    static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
    static char pending[65536];
    static size_t pending_length = 0;
    /* A forked child, which never logged `P`, and a process past its exit write events as they happen. */
    static int unbuffered = 0;

    static void write_all(const char *data, size_t length) {
        while (length > 0) {
            ssize_t written = write(log_fd, data, length);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) return;
            data += written;
            length -= (size_t)written;
        }
    }

    static void flush_locked(void) {
        write_all(pending, pending_length);
        pending_length = 0;
    }

    static void append(const char *data, size_t length) {
        if (log_fd < 0) return;
        pthread_mutex_lock(&log_lock);
        if (unbuffered || length > sizeof pending) {
            flush_locked();
            write_all(data, length);
        } else {
            if (pending_length + length > sizeof pending) flush_locked();
            memcpy(pending + pending_length, data, length);
            pending_length += length;
        }
        pthread_mutex_unlock(&log_lock);
    }

    /* Takes the lock within about 100 ms. A signal handler that spawns or exits while its own thread appends would
       otherwise wait forever; skipping its write leaves the process without `F`, which only makes the run uncacheable. */
    static int acquire(void) {
        for (int attempt = 0; attempt < 1000; attempt++) {
            if (pthread_mutex_trylock(&log_lock) == 0) return 1;
            usleep(100);
        }
        return 0;
    }

    static void flush(void) {
        if (log_fd < 0 || !acquire()) return;
        flush_locked();
        pthread_mutex_unlock(&log_lock);
    }

    /* Writes this program's events and `F`, before it exits or execs. `final`: it exits, so later events (from
       other exit handlers) are written as they happen. An exec that fails logs `Y` or `Z`, which reopens it. */
    #if defined(__linux__)
    static void loaded_libraries(void);
    #endif
    static void seal(int final) {
        if (log_fd < 0) return;
    #if defined(__linux__)
        loaded_libraries();
    #endif
        char line[32];
        int length = snprintf(line, sizeof line, "%d\tF\t\n", getpid());
        if (!acquire()) return;
        flush_locked();
        if (length > 0) write_all(line, (size_t)length);
        if (final) unbuffered = 1;
        pthread_mutex_unlock(&log_lock);
    }

    static void emit(char kind, const char *text) {
        if (log_fd < 0 || text == NULL) return;
        char line[MAXPATHLEN * 2 + 64];
        int length = snprintf(line, sizeof line, "%d\t%c\t%s\n", getpid(), kind, text);
        if (length <= 0) return;
        if ((size_t)length >= sizeof line || strchr(text, '\n') != NULL) {
            length = snprintf(line, sizeof line, "%d\t?\tunrepresentable\n", getpid());
        }
        append(line, (size_t)length);
    }

    /* The path an open descriptor names. */
    static int descriptor_path(int descriptor, char *path, size_t size) {
    #if defined(__APPLE__)
        (void)size;
        return fcntl(descriptor, F_GETPATH, path) == -1 ? -1 : 0;
    #else
        char link[64];
        snprintf(link, sizeof link, "/proc/self/fd/%d", descriptor);
        ssize_t length = REAL(readlink)(link, path, size - 1);
        if (length < 0) return -1;
        path[length] = 0;
        return 0;
    #endif
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
        } else if (descriptor_path(directory, base, sizeof base) == -1) {
            emit('?', "dirfd");
            return;
        }
        snprintf(absolute, sizeof absolute, "%s/%s", base, path);
        emit(kind, absolute);
    }

    static void before_fork(void) {
        pthread_mutex_lock(&log_lock);
        if (log_fd >= 0) flush_locked();
    }
    static void after_fork_parent(void) { pthread_mutex_unlock(&log_lock); }
    static void after_fork_child(void) {
        pending_length = 0;
        unbuffered = 1;
        pthread_mutex_unlock(&log_lock);
    }

    #if defined(__linux__)
    /* The block the kernel copied this process's environment into. Rust's `env::vars`, which a `Command` with an
       environment of its own also calls, reads `environ` directly rather than through a function this library could
       interpose, and measures every entry with `strlen`: a measurement of an entry's start is the read. `getenv`'s values
       start after a `=`. */
    static const char *environment_start = NULL, *environment_end = NULL;
    static int environment_read = 0;

    /* What the program and the libraries it was started with are: the system linker, `cc1` and their libraries are
       inputs like the files they read. Libraries the program opens later through `dlopen` are found by the loader,
       which this library does not see. */
    static char own_library[MAXPATHLEN];
    static int loaded(struct dl_phdr_info *info, size_t size, void *unused) {
        (void)size;
        (void)unused;
        if (info->dlpi_name != NULL && info->dlpi_name[0] == '/' && strcmp(info->dlpi_name, own_library) != 0) {
            emit('R', info->dlpi_name);
        }
        return 0;
    }
    /* Logged when the process starts and again when it seals its events, which also covers libraries it opened with
       `dlopen` (a linker plugin), without wrapping `dlopen`: a wrapper would become the caller whose `RUNPATH` the loader
       searches. A library closed again before then is not seen. */
    static void loaded_libraries(void) {
        if (!ready) return;
        int saved = errno;
        depth++;
        dl_iterate_phdr(loaded, NULL);
        depth--;
        errno = saved;
    }
    #endif

    __attribute__((constructor)) static void start(void) {
        if (!START_DEPTH()) return;
        depth++;
        char executable[MAXPATHLEN];
    #if defined(__APPLE__)
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
    #else
        ssize_t length = REAL(readlink)("/proc/self/exe", executable, sizeof executable - 1);
        int located = length > 0;
        if (located) executable[length] = 0;
    #endif
        const char *log = REAL(getenv)("TUIST_CARGO_READ_LOG");
        if (log != NULL) log_fd = REAL(open)(log, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
        const char *root = REAL(getenv)("TUIST_CARGO_READ_TOOLCHAIN");
        if (root != NULL) strlcpy(toolchain, root, sizeof toolchain);
        emit('P', located ? executable : "?");
        /* The environment the process started with, which the key holds: a query's own is logged against it. */
        char **current = ENVIRON;
        size_t count = 0;
        while (current != NULL && current[count] != NULL) count++;
        initial_environment = calloc(count + 1, sizeof(char *));
        for (size_t index = 0; initial_environment != NULL && index < count; index++) {
            initial_environment[index] = strdup(current[index]);
        }
        char parent[32];
        snprintf(parent, sizeof parent, "%d", getppid());
        emit('p', parent);
    #if defined(__linux__)
        if (located) emit('R', executable);
        Dl_info own;
        if (dladdr((const void *)&start, &own) != 0 && own.dli_fname != NULL) {
            strlcpy(own_library, own.dli_fname, sizeof own_library);
        }
        dl_iterate_phdr(loaded, NULL);
        for (size_t index = 0; index < count; index++) {
            const char *end = current[index] + strlen(current[index]) + 1;
            if (environment_start == NULL || current[index] < environment_start) environment_start = current[index];
            if (end > environment_end) environment_end = end;
        }
    #endif
        pthread_atfork(before_fork, after_fork_parent, after_fork_child);
        ready = 1;
        depth--;
    }

    __attribute__((destructor)) static void stop(void) { seal(1); }

    /* `exit` runs the destructor; these end the process without it. */
    __attribute__((noreturn)) static void my__exit(int status) { seal(1); REAL(_exit)(status); __builtin_unreachable(); }
    INTERPOSE(my__exit, _exit)
    __attribute__((noreturn)) static void my_Exit(int status) { seal(1); REAL(_Exit)(status); __builtin_unreachable(); }
    INTERPOSE(my_Exit, _Exit)

    /* Whether the calling code is the toolchain's or the system's, whose own environment reads are not the crate's. On
       Linux the C library's own reads do not reach this library, and every other program's are the run's. */
    static int from_toolchain(const void *caller) {
        Dl_info info;
        if (!ready || dladdr(caller, &info) == 0 || info.dli_fname == NULL) return 1;
    #if defined(__APPLE__)
        if (strncmp(info.dli_fname, "/usr/lib/", 9) == 0 || strncmp(info.dli_fname, "/System/", 8) == 0) return 1;
    #endif
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
        if (flags & TAKES_MODE) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
        int result = REAL(open)(path, flags, mode);
        if (ready && depth == 0) { int saved = errno; depth++; opened(AT_FDCWD, path, flags, result); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_open, open)

    static int my_openat(int directory, const char *path, int flags, ...) {
        int mode = 0;
        if (flags & TAKES_MODE) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
        int result = REAL(openat)(directory, path, flags, mode);
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

    static int my_stat(const char *path, struct stat *value) { int r = REAL(stat)(path, value); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_stat, stat)
    static int my_lstat(const char *path, struct stat *value) { int r = REAL(lstat)(path, value); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_lstat, lstat)
    static int my_fstatat(int directory, const char *path, struct stat *value, int flags) {
        int r = REAL(fstatat)(directory, path, value, flags);
    #if defined(__linux__)
        /* A descriptor's own status, not a lookup. */
        if ((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0) return r;
    #endif
        looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_fstatat, fstatat)
    static int my_access(const char *path, int mode) { int r = REAL(access)(path, mode); looked_up(AT_FDCWD, path, r); return r; }
    INTERPOSE(my_access, access)
    static ssize_t my_readlink(const char *path, char *buffer, size_t size) {
        ssize_t r = REAL(readlink)(path, buffer, size);
        looked_up(AT_FDCWD, path, r >= 0 ? 0 : -1);
        return r;
    }
    INTERPOSE(my_readlink, readlink)

    static DIR *my_opendir(const char *path) {
        DIR *result = REAL(opendir)(path);
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
        char *result = REAL(getenv)(name);
        if (ready && depth == 0 && name != NULL && !from_toolchain(__builtin_return_address(0))) {
            depth++;
            emit('E', name);
            depth--;
        }
        return result;
    }
    INTERPOSE(my_getenv, getenv)

    #if defined(__APPLE__)
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
    #endif

    static void spawned(const char *path, char *const environment[]) {
        if (!ready || depth != 0) return;
        depth++;
        emit('X', path);
    #if defined(__APPLE__)
        if (environment == *_NSGetEnviron()) emit('x', "*");
    #else
        (void)environment;
    #endif
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

    #if GLIBC_AT_LEAST(2, 29)
    static int my_addchdir(posix_spawn_file_actions_t *actions, const char *path) {
        mark_chdir(actions, 1);
        return REAL(posix_spawn_file_actions_addchdir_np)(actions, path);
    }
    INTERPOSE(my_addchdir, posix_spawn_file_actions_addchdir_np)
    static int my_addfchdir(posix_spawn_file_actions_t *actions, int directory) {
        mark_chdir(actions, 1);
        return REAL(posix_spawn_file_actions_addfchdir_np)(actions, directory);
    }
    INTERPOSE(my_addfchdir, posix_spawn_file_actions_addfchdir_np)
    #endif
    #if defined(__APPLE__) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
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
        return REAL(posix_spawn_file_actions_destroy)(actions);
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
    #if defined(__APPLE__)
        const char *programs[] = { "git", "sw_vers", "uname", "xcode-select", "xcrun", "codesign", "swiftc", "ar", "ranlib" };
    #else
        /* Every other program loads this library and is recorded like the run itself. */
        const char *programs[] = { "git", "uname" };
    #endif
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
            const char *search = REAL(getenv)("PATH");
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
                if (stat(candidate, &value) == 0 && S_ISREG(value.st_mode) && REAL(access)(candidate, X_OK) == 0) {
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
        append(line, (size_t)length);
    #if defined(__APPLE__)
        if (environment == *_NSGetEnviron()) emit('x', "*");
    #endif
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
        seal(0);
        int result = REAL(execve)(path, arguments, environment);
        if (logged) { int saved = errno; depth++; emit(query ? 'Z' : 'Y', path); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_execve, execve)

    /* `POSIX_SPAWN_SETEXEC` replaces this process like `execve`, so a successful one does not return either. */
    static int replaces_process(const posix_spawnattr_t *attributes) {
    #if defined(POSIX_SPAWN_SETEXEC)
        short flags = 0;
        return attributes != NULL && posix_spawnattr_getflags(attributes, &flags) == 0 && (flags & POSIX_SPAWN_SETEXEC);
    #else
        (void)attributes;
        return 0;
    #endif
    }

    /* Spawns are logged once they succeed, and the real call runs with the guard held: `posix_spawnp` searches
       PATH through `posix_spawn`, whose attempts are not separate spawns. One that replaces the process is logged
       before, and withdrawn when it fails. */
    #define SPAWN(call, path, actions, attributes, arguments, environment) \
        int replacing = replaces_process(attributes), logged = ready && depth == 0, replaces = logged && replacing; \
        if (replaces) spawned(path, environment); \
        if (replacing) seal(0); else flush(); \
        depth++; \
        int result = call; \
        depth--; \
        if (replaces && result != 0) { depth++; emit('Y', path); depth--; } \
        if (logged && !replaces && result == 0 && !queried(path, actions, arguments, environment)) spawned(path, environment); \
        return result;
    static int my_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        SPAWN(REAL(posix_spawn)(pid, path, actions, attributes, arguments, environment), path, actions, attributes,
              arguments, environment)
    }
    INTERPOSE(my_posix_spawn, posix_spawn)
    static int my_posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        SPAWN(REAL(posix_spawnp)(pid, file, actions, attributes, arguments, environment), file, actions, attributes,
              arguments, environment)
    }
    INTERPOSE(my_posix_spawnp, posix_spawnp)
    #if defined(__linux__) && GLIBC_AT_LEAST(2, 39)
    /* `posix_spawn` that returns a descriptor for the child, which glibc implements without the symbols above. */
    REAL_DECLARE(pidfd_spawn)
    REAL_DECLARE(pidfd_spawnp)
    static int my_pidfd_spawn(int *pidfd, const char *path, const posix_spawn_file_actions_t *actions,
                              const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        SPAWN(REAL(pidfd_spawn)(pidfd, path, actions, attributes, arguments, environment), path, actions, attributes,
              arguments, environment)
    }
    INTERPOSE(my_pidfd_spawn, pidfd_spawn)
    static int my_pidfd_spawnp(int *pidfd, const char *file, const posix_spawn_file_actions_t *actions,
                               const posix_spawnattr_t *attributes, char *const arguments[], char *const environment[]) {
        SPAWN(REAL(pidfd_spawnp)(pidfd, file, actions, attributes, arguments, environment), file, actions, attributes,
              arguments, environment)
    }
    INTERPOSE(my_pidfd_spawnp, pidfd_spawnp)
    #endif

    static int my_connect(int socket, const struct sockaddr *address, socklen_t length) {
        if (ready && depth == 0) {
            depth++;
            if (address && address->sa_family == AF_UNIX) emit('N', ((const struct sockaddr_un *)address)->sun_path);
            else emit('N', "connect");
            depth--;
        }
        return REAL(connect)(socket, address, length);
    }
    INTERPOSE(my_connect, connect)

    #if defined(__linux__)
    /* glibc's functions call each other directly, not through the symbols this library replaces, so each entry point that
       opens, looks up, lists or starts something is recorded on its own, and the ones it cannot record make the run
       uncacheable: `fopen` does not reach `open`, nor `execvp` `execve`, nor `system` `posix_spawn`. Programs built
       against older glibc call `__xstat64` for `stat`, and fortified ones `__open_2` and `__realpath_chk`. */
    REAL_DECLARE(open64)
    REAL_DECLARE(openat64)
    REAL_DECLARE(__open_2)
    REAL_DECLARE(__open64_2)
    REAL_DECLARE(__openat_2)
    REAL_DECLARE(__openat64_2)
    REAL_DECLARE(creat)
    REAL_DECLARE(creat64)
    REAL_DECLARE(fopen)
    REAL_DECLARE(fopen64)
    REAL_DECLARE(freopen)
    REAL_DECLARE(freopen64)
    REAL_DECLARE(stat64)
    REAL_DECLARE(lstat64)
    REAL_DECLARE(fstatat64)
    REAL_DECLARE(__xstat)
    REAL_DECLARE(__lxstat)
    REAL_DECLARE(__fxstatat)
    REAL_DECLARE(__xstat64)
    REAL_DECLARE(__lxstat64)
    REAL_DECLARE(__fxstatat64)
    #if GLIBC_AT_LEAST(2, 28)
    REAL_DECLARE(statx)
    #endif
    REAL_DECLARE(faccessat)
    REAL_DECLARE(euidaccess)
    REAL_DECLARE(eaccess)
    REAL_DECLARE(readlinkat)
    REAL_DECLARE(realpath)
    REAL_DECLARE(canonicalize_file_name)
    REAL_DECLARE(fdopendir)
    REAL_DECLARE(scandir)
    REAL_DECLARE(scandir64)
    REAL_DECLARE(secure_getenv)
    REAL_DECLARE(strlen)
    REAL_DECLARE(execvp)
    REAL_DECLARE(execvpe)
    REAL_DECLARE(fexecve)
    REAL_DECLARE(system)
    REAL_DECLARE(popen)
    REAL_DECLARE(__realpath_chk)
    REAL_DECLARE(__readlink_chk)
    REAL_DECLARE(__readlinkat_chk)
    REAL_DECLARE(__open)
    REAL_DECLARE(__open64)
    REAL_DECLARE(syscall)
    REAL_DECLARE(mkstemp)
    REAL_DECLARE(mkostemp)
    REAL_DECLARE(mkstemps)
    REAL_DECLARE(mkostemps)
    REAL_DECLARE(mkstemp64)
    REAL_DECLARE(mkostemp64)
    REAL_DECLARE(mkstemps64)
    REAL_DECLARE(mkostemps64)

    #define OPEN_MODE(flags, last) \
        int mode = 0; \
        if ((flags) & TAKES_MODE) { va_list list; va_start(list, last); mode = va_arg(list, int); va_end(list); }
    #define RECORD_OPEN(directory, path, flags, result) \
        if (ready && depth == 0) { int saved = errno; depth++; opened((directory), (path), (flags), (result)); depth--; errno = saved; }

    static int my_open64(const char *path, int flags, ...) {
        OPEN_MODE(flags, flags)
        int result = REAL(open64)(path, flags, mode);
        RECORD_OPEN(AT_FDCWD, path, flags, result)
        return result;
    }
    INTERPOSE(my_open64, open64)
    static int my_openat64(int directory, const char *path, int flags, ...) {
        OPEN_MODE(flags, flags)
        int result = REAL(openat64)(directory, path, flags, mode);
        RECORD_OPEN(directory, path, flags, result)
        return result;
    }
    INTERPOSE(my_openat64, openat64)
    static int my_open_2(const char *path, int flags) {
        int result = REAL(__open_2)(path, flags);
        RECORD_OPEN(AT_FDCWD, path, flags, result)
        return result;
    }
    INTERPOSE(my_open_2, __open_2)
    static int my_open64_2(const char *path, int flags) {
        int result = REAL(__open64_2)(path, flags);
        RECORD_OPEN(AT_FDCWD, path, flags, result)
        return result;
    }
    INTERPOSE(my_open64_2, __open64_2)
    static int my_openat_2(int directory, const char *path, int flags) {
        int result = REAL(__openat_2)(directory, path, flags);
        RECORD_OPEN(directory, path, flags, result)
        return result;
    }
    INTERPOSE(my_openat_2, __openat_2)
    static int my_openat64_2(int directory, const char *path, int flags) {
        int result = REAL(__openat64_2)(directory, path, flags);
        RECORD_OPEN(directory, path, flags, result)
        return result;
    }
    INTERPOSE(my_openat64_2, __openat64_2)
    static int my__open(const char *path, int flags, ...) {
        OPEN_MODE(flags, flags)
        int result = REAL(__open)(path, flags, mode);
        RECORD_OPEN(AT_FDCWD, path, flags, result)
        return result;
    }
    INTERPOSE(my__open, __open)
    static int my__open64(const char *path, int flags, ...) {
        OPEN_MODE(flags, flags)
        int result = REAL(__open64)(path, flags, mode);
        RECORD_OPEN(AT_FDCWD, path, flags, result)
        return result;
    }
    INTERPOSE(my__open64, __open64)
    static int my_creat(const char *path, mode_t mode) {
        int result = REAL(creat)(path, mode);
        RECORD_OPEN(AT_FDCWD, path, O_CREAT | O_WRONLY | O_TRUNC, result)
        return result;
    }
    INTERPOSE(my_creat, creat)
    static int my_creat64(const char *path, mode_t mode) {
        int result = REAL(creat64)(path, mode);
        RECORD_OPEN(AT_FDCWD, path, O_CREAT | O_WRONLY | O_TRUNC, result)
        return result;
    }
    INTERPOSE(my_creat64, creat64)

    static void streamed(const char *path, const char *mode, FILE *result) {
        if (!ready || depth != 0 || path == NULL || mode == NULL) return;
        int saved = errno;
        depth++;
        opened(AT_FDCWD, path, strpbrk(mode, "wa+") != NULL ? O_WRONLY : O_RDONLY, result == NULL ? -1 : fileno(result));
        depth--;
        errno = saved;
    }
    static FILE *my_fopen(const char *path, const char *mode) {
        FILE *result = REAL(fopen)(path, mode);
        streamed(path, mode, result);
        return result;
    }
    INTERPOSE(my_fopen, fopen)
    static FILE *my_fopen64(const char *path, const char *mode) {
        FILE *result = REAL(fopen64)(path, mode);
        streamed(path, mode, result);
        return result;
    }
    INTERPOSE(my_fopen64, fopen64)
    static FILE *my_freopen(const char *path, const char *mode, FILE *stream) {
        FILE *result = REAL(freopen)(path, mode, stream);
        streamed(path, mode, result);
        return result;
    }
    INTERPOSE(my_freopen, freopen)
    static FILE *my_freopen64(const char *path, const char *mode, FILE *stream) {
        FILE *result = REAL(freopen64)(path, mode, stream);
        streamed(path, mode, result);
        return result;
    }
    INTERPOSE(my_freopen64, freopen64)

    static int my_stat64(const char *path, struct stat64 *value) {
        int r = REAL(stat64)(path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_stat64, stat64)
    static int my_lstat64(const char *path, struct stat64 *value) {
        int r = REAL(lstat64)(path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_lstat64, lstat64)
    static int my_fstatat64(int directory, const char *path, struct stat64 *value, int flags) {
        int r = REAL(fstatat64)(directory, path, value, flags);
        if (!((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0)) looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_fstatat64, fstatat64)
    static int my_xstat(int version, const char *path, struct stat *value) {
        int r = REAL(__xstat)(version, path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_xstat, __xstat)
    static int my_lxstat(int version, const char *path, struct stat *value) {
        int r = REAL(__lxstat)(version, path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_lxstat, __lxstat)
    static int my_fxstatat(int version, int directory, const char *path, struct stat *value, int flags) {
        int r = REAL(__fxstatat)(version, directory, path, value, flags);
        if (!((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0)) looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_fxstatat, __fxstatat)
    static int my_xstat64(int version, const char *path, struct stat64 *value) {
        int r = REAL(__xstat64)(version, path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_xstat64, __xstat64)
    static int my_lxstat64(int version, const char *path, struct stat64 *value) {
        int r = REAL(__lxstat64)(version, path, value);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_lxstat64, __lxstat64)
    static int my_fxstatat64(int version, int directory, const char *path, struct stat64 *value, int flags) {
        int r = REAL(__fxstatat64)(version, directory, path, value, flags);
        if (!((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0)) looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_fxstatat64, __fxstatat64)
    #if GLIBC_AT_LEAST(2, 28)
    /* Rust's standard library looks files up with `statx`, through the symbol when the C library has one. */
    static int my_statx(int directory, const char *path, int flags, unsigned int mask, struct statx *value) {
        int r = REAL(statx)(directory, path, flags, mask, value);
        if (!((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0)) looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_statx, statx)
    #endif
    static int my_faccessat(int directory, const char *path, int mode, int flags) {
        int r = REAL(faccessat)(directory, path, mode, flags);
        if (!((flags & AT_EMPTY_PATH) && path != NULL && path[0] == 0)) looked_up(directory, path, r);
        return r;
    }
    INTERPOSE(my_faccessat, faccessat)
    static int my_euidaccess(const char *path, int mode) {
        int r = REAL(euidaccess)(path, mode);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_euidaccess, euidaccess)
    static int my_eaccess(const char *path, int mode) {
        int r = REAL(eaccess)(path, mode);
        looked_up(AT_FDCWD, path, r);
        return r;
    }
    INTERPOSE(my_eaccess, eaccess)
    static ssize_t my_readlinkat(int directory, const char *path, char *buffer, size_t size) {
        ssize_t r = REAL(readlinkat)(directory, path, buffer, size);
        looked_up(directory, path, r >= 0 ? 0 : -1);
        return r;
    }
    INTERPOSE(my_readlinkat, readlinkat)
    static ssize_t my_readlink_chk(const char *path, char *buffer, size_t size, size_t capacity) {
        ssize_t r = REAL(__readlink_chk)(path, buffer, size, capacity);
        looked_up(AT_FDCWD, path, r >= 0 ? 0 : -1);
        return r;
    }
    INTERPOSE(my_readlink_chk, __readlink_chk)
    static ssize_t my_readlinkat_chk(int directory, const char *path, char *buffer, size_t size, size_t capacity) {
        ssize_t r = REAL(__readlinkat_chk)(directory, path, buffer, size, capacity);
        looked_up(directory, path, r >= 0 ? 0 : -1);
        return r;
    }
    INTERPOSE(my_readlinkat_chk, __readlinkat_chk)
    /* The path and what it resolves to, which `canonicalize` returns. */
    static void resolved_path(const char *path, const char *result) {
        if (!ready || depth != 0 || path == NULL) return;
        int saved = errno;
        looked_up(AT_FDCWD, path, result != NULL ? 0 : -1);
        if (result != NULL) looked_up(AT_FDCWD, result, 0);
        errno = saved;
    }
    static char *my_realpath(const char *path, char *resolved) {
        char *result = REAL(realpath)(path, resolved);
        resolved_path(path, result);
        return result;
    }
    INTERPOSE(my_realpath, realpath)
    static char *my_realpath_chk(const char *path, char *resolved, size_t capacity) {
        char *result = REAL(__realpath_chk)(path, resolved, capacity);
        resolved_path(path, result);
        return result;
    }
    INTERPOSE(my_realpath_chk, __realpath_chk)
    static char *my_canonicalize_file_name(const char *path) {
        char *result = REAL(canonicalize_file_name)(path);
        resolved_path(path, result);
        return result;
    }
    INTERPOSE(my_canonicalize_file_name, canonicalize_file_name)

    static void listed(int descriptor, const char *path, int found) {
        if (!ready || depth != 0) return;
        int saved = errno;
        depth++;
        char named[MAXPATHLEN];
        if (path == NULL && found && descriptor_path(descriptor, named, sizeof named) == 0) path = named;
        if (found) {
            if (path != NULL) emit_path('D', AT_FDCWD, path); else emit('?', "listing");
        } else if (path != NULL && (saved == ENOENT || saved == ENOTDIR)) {
            emit_path('A', AT_FDCWD, path);
        }
        depth--;
        errno = saved;
    }
    static DIR *my_fdopendir(int descriptor) {
        DIR *result = REAL(fdopendir)(descriptor);
        if (result != NULL) listed(descriptor, NULL, 1);
        return result;
    }
    INTERPOSE(my_fdopendir, fdopendir)
    static int my_scandir(const char *path, struct dirent ***names, int (*filter)(const struct dirent *),
                          int (*compare)(const struct dirent **, const struct dirent **)) {
        int result = REAL(scandir)(path, names, filter, compare);
        listed(-1, path, result >= 0);
        return result;
    }
    INTERPOSE(my_scandir, scandir)
    static int my_scandir64(const char *path, struct dirent64 ***names, int (*filter)(const struct dirent64 *),
                            int (*compare)(const struct dirent64 **, const struct dirent64 **)) {
        int result = REAL(scandir64)(path, names, filter, compare);
        listed(-1, path, result >= 0);
        return result;
    }
    INTERPOSE(my_scandir64, scandir64)
    /* Walks of a whole tree read listings and statuses the C library makes itself, `getdents64` lists a descriptor
       without naming it, `open_by_handle_at` opens a file without a path, `execveat` starts a program by descriptor, and
       `wordexp` expands variables and runs commands in a shell: a run that does any of them is not cached. */
    #define UNOBSERVED(name, ret, params, args) \
        REAL_DECLARE(name) \
        static ret my_##name params { \
            if (ready && depth == 0) { depth++; emit('?', #name); depth--; } \
            return REAL(name) args; \
        } \
        INTERPOSE(my_##name, name)
    UNOBSERVED(nftw, int, (const char *a, int (*b)(const char *, const struct stat *, int, struct FTW *), int c, int d), (a, b, c, d))
    UNOBSERVED(nftw64, int, (const char *a, int (*b)(const char *, const struct stat64 *, int, struct FTW *), int c, int d), (a, b, c, d))
    UNOBSERVED(ftw, int, (const char *a, int (*b)(const char *, const struct stat *, int), int c), (a, b, c))
    UNOBSERVED(ftw64, int, (const char *a, int (*b)(const char *, const struct stat64 *, int), int c), (a, b, c))
    UNOBSERVED(fts_open, FTS *, (char *const *a, int b, int (*c)(const FTSENT **, const FTSENT **)), (a, b, c))
    UNOBSERVED(fts64_open, FTS64 *, (char *const *a, int b, int (*c)(const FTSENT64 **, const FTSENT64 **)), (a, b, c))
    UNOBSERVED(scandirat, int, (int a, const char *b, struct dirent ***c, int (*d)(const struct dirent *),
                                int (*e)(const struct dirent **, const struct dirent **)), (a, b, c, d, e))
    UNOBSERVED(scandirat64, int, (int a, const char *b, struct dirent64 ***c, int (*d)(const struct dirent64 *),
                                  int (*e)(const struct dirent64 **, const struct dirent64 **)), (a, b, c, d, e))
    UNOBSERVED(getdents64, ssize_t, (int a, void *b, size_t c), (a, b, c))
    UNOBSERVED(getdirentries, ssize_t, (int a, char *b, size_t c, off_t *d), (a, b, c, d))
    UNOBSERVED(getdirentries64, ssize_t, (int a, char *b, size_t c, off64_t *d), (a, b, c, d))
    UNOBSERVED(open_by_handle_at, int, (int a, struct file_handle *b, int c), (a, b, c))
    UNOBSERVED(wordexp, int, (const char *a, wordexp_t *b, int c), (a, b, c))
    UNOBSERVED(glob, int, (const char *a, int b, int (*c)(const char *, int), glob_t *d), (a, b, c, d))
    UNOBSERVED(glob64, int, (const char *a, int b, int (*c)(const char *, int), glob64_t *d), (a, b, c, d))
    #if GLIBC_AT_LEAST(2, 34)
    UNOBSERVED(execveat, int, (int a, const char *b, char *const c[], char *const d[], int e), (a, b, c, d, e))
    #endif

    /* glibc's `secure_getenv` calls `getenv` through its symbol, which would name this library as the reader. */
    static char *my_secure_getenv(const char *name) {
        depth++;
        char *result = REAL(secure_getenv)(name);
        depth--;
        if (ready && depth == 0 && name != NULL && !from_toolchain(__builtin_return_address(0))) {
            depth++;
            emit('E', name);
            depth--;
        }
        return result;
    }
    INTERPOSE(my_secure_getenv, secure_getenv)

    static size_t my_strlen(const char *text) {
        if (text >= environment_start && text < environment_end && (text == environment_start || text[-1] == 0)
            && !environment_read && ready && depth == 0 && !from_toolchain(__builtin_return_address(0))) {
            environment_read = 1;
            depth++;
            emit('e', "*");
            depth--;
        }
        return REAL(strlen)(text);
    }
    INTERPOSE(my_strlen, strlen)

    static int my_execv(const char *path, char *const arguments[]) { return my_execve(path, arguments, environ); }
    INTERPOSE(my_execv, execv)

    /* `execvp` searches `PATH` itself, as a forked Rust child does when its command sets `PATH`. */
    static int searched_exec(const char *file, char *const arguments[], char *const environment[], int explicit) {
        int logged = ready && depth == 0, query = 0;
        if (logged && log_fd >= 0 && !queries_unknown) {
            depth++;
            query = log_query('J', file, 1, NULL, arguments, environment);
            depth--;
        }
        if (!query) spawned(file, environment);
        seal(0);
        int result = explicit ? REAL(execvpe)(file, arguments, environment) : REAL(execvp)(file, arguments);
        if (logged) { int saved = errno; depth++; emit(query ? 'Z' : 'Y', file); depth--; errno = saved; }
        return result;
    }
    static int my_execvp(const char *file, char *const arguments[]) { return searched_exec(file, arguments, environ, 0); }
    INTERPOSE(my_execvp, execvp)
    static int my_execvpe(const char *file, char *const arguments[], char *const environment[]) {
        return searched_exec(file, arguments, environment, 1);
    }
    INTERPOSE(my_execvpe, execvpe)

    #define COLLECT(arguments, first, list) \
        va_list list, counting; \
        va_start(list, first); \
        va_copy(counting, list); \
        size_t count = 1; \
        while (va_arg(counting, char *) != NULL) count++; \
        va_end(counting); \
        char **arguments = alloca((count + 1) * sizeof(char *)); \
        arguments[0] = (char *)(first); \
        for (size_t index = 1; index <= count; index++) arguments[index] = va_arg(list, char *);
    static int my_execl(const char *path, const char *first, ...) {
        COLLECT(arguments, first, list)
        va_end(list);
        return my_execve(path, arguments, environ);
    }
    INTERPOSE(my_execl, execl)
    static int my_execlp(const char *file, const char *first, ...) {
        COLLECT(arguments, first, list)
        va_end(list);
        return searched_exec(file, arguments, environ, 0);
    }
    INTERPOSE(my_execlp, execlp)
    static int my_execle(const char *path, const char *first, ...) {
        COLLECT(arguments, first, list)
        char **environment = va_arg(list, char **);
        va_end(list);
        return my_execve(path, arguments, environment);
    }
    INTERPOSE(my_execle, execle)
    static int my_fexecve(int descriptor, char *const arguments[], char *const environment[]) {
        char path[MAXPATHLEN];
        int logged = ready && depth == 0;
        if (descriptor_path(descriptor, path, sizeof path) != 0) strlcpy(path, "?", sizeof path);
        spawned(path, environment);
        seal(0);
        int result = REAL(fexecve)(descriptor, arguments, environment);
        if (logged) { int saved = errno; depth++; emit('Y', path); depth--; errno = saved; }
        return result;
    }
    INTERPOSE(my_fexecve, fexecve)

    /* These start `/bin/sh` without `posix_spawn`'s symbol. */
    static int my_system(const char *command) {
        spawned("/bin/sh", environ);
        flush();
        return REAL(system)(command);
    }
    INTERPOSE(my_system, system)
    static FILE *my_popen(const char *command, const char *mode) {
        flush();
        FILE *result = REAL(popen)(command, mode);
        if (result != NULL) spawned("/bin/sh", environ);
        return result;
    }
    INTERPOSE(my_popen, popen)
    /* Programs that make system calls themselves, rather than through the functions above. Those that name a path or
       start a program are not seen: a run that makes one is not cached. */
    static int unobserved_call(long number) {
        switch (number) {
    #define CALL(name) case name:
    #if defined(SYS_open)
        CALL(SYS_open)
    #endif
    #if defined(SYS_creat)
        CALL(SYS_creat)
    #endif
    #if defined(SYS_stat)
        CALL(SYS_stat)
    #endif
    #if defined(SYS_lstat)
        CALL(SYS_lstat)
    #endif
    #if defined(SYS_access)
        CALL(SYS_access)
    #endif
    #if defined(SYS_readlink)
        CALL(SYS_readlink)
    #endif
    #if defined(SYS_getdents)
        CALL(SYS_getdents)
    #endif
    #if defined(SYS_fork)
        CALL(SYS_fork)
    #endif
    #if defined(SYS_vfork)
        CALL(SYS_vfork)
    #endif
    #if defined(SYS_newfstatat)
        CALL(SYS_newfstatat)
    #endif
    #if defined(SYS_openat2)
        CALL(SYS_openat2)
    #endif
    #if defined(SYS_faccessat2)
        CALL(SYS_faccessat2)
    #endif
    #if defined(SYS_clone3)
        CALL(SYS_clone3)
    #endif
        CALL(SYS_openat) CALL(SYS_statx) CALL(SYS_faccessat) CALL(SYS_readlinkat) CALL(SYS_getdents64)
        CALL(SYS_open_by_handle_at) CALL(SYS_execve) CALL(SYS_execveat) CALL(SYS_clone)
    #undef CALL
            return 1;
        default:
            return 0;
        }
    }
    static long my_syscall(long number, ...) {
        va_list list;
        va_start(list, number);
        long a = va_arg(list, long), b = va_arg(list, long), c = va_arg(list, long);
        long d = va_arg(list, long), e = va_arg(list, long), f = va_arg(list, long);
        va_end(list);
        if (ready && depth == 0 && unobserved_call(number)) { int saved = errno; depth++; emit('?', "syscall"); depth--; errno = saved; }
        return REAL(syscall)(number, a, b, c, d, e, f);
    }
    INTERPOSE(my_syscall, syscall)

    /* Temporary files the C library opens itself. */
    static void created(const char *path, int result) {
        if (result < 0 || !ready || depth != 0) return;
        int saved = errno;
        depth++;
        emit_path('W', AT_FDCWD, path);
        depth--;
        errno = saved;
    }
    static int my_mkstemp(char *path) { int r = REAL(mkstemp)(path); created(path, r); return r; }
    INTERPOSE(my_mkstemp, mkstemp)
    static int my_mkostemp(char *path, int flags) { int r = REAL(mkostemp)(path, flags); created(path, r); return r; }
    INTERPOSE(my_mkostemp, mkostemp)
    static int my_mkstemps(char *path, int suffix) { int r = REAL(mkstemps)(path, suffix); created(path, r); return r; }
    INTERPOSE(my_mkstemps, mkstemps)
    static int my_mkostemps(char *path, int suffix, int flags) {
        int r = REAL(mkostemps)(path, suffix, flags);
        created(path, r);
        return r;
    }
    INTERPOSE(my_mkostemps, mkostemps)
    static int my_mkstemp64(char *path) { int r = REAL(mkstemp64)(path); created(path, r); return r; }
    INTERPOSE(my_mkstemp64, mkstemp64)
    static int my_mkostemp64(char *path, int flags) { int r = REAL(mkostemp64)(path, flags); created(path, r); return r; }
    INTERPOSE(my_mkostemp64, mkostemp64)
    static int my_mkstemps64(char *path, int suffix) { int r = REAL(mkstemps64)(path, suffix); created(path, r); return r; }
    INTERPOSE(my_mkstemps64, mkstemps64)
    static int my_mkostemps64(char *path, int suffix, int flags) {
        int r = REAL(mkostemps64)(path, suffix, flags);
        created(path, r);
        return r;
    }
    INTERPOSE(my_mkostemps64, mkostemps64)
    #endif
    """#
}
