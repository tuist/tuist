#if canImport(Compression)
    import Compression
#endif
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif
import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistGit
import TuistServer

/// Code coverage of a `tuist cargo` test run, reported as the server's build-system-neutral `coverage` block and,
/// where the run's processes say which test executed what, `coverage_evidence`.
///
/// The build is instrumented with `-C instrument-coverage`. Every test process is started through a target runner
/// (`runnerScript`) that records its arguments and points `LLVM_PROFILE_FILE` at a profile of its own, so each
/// profile is known to belong to one test binary and, under nextest, which runs each test in its own process, to one
/// test. Plain `cargo test` runs a binary's tests together in one process, so its processes give `target` evidence
/// only. Once the tests ran, `llvm-profdata` and `llvm-cov` (the `llvm-tools` rustup component) read the profiles
/// against the test binaries: all of them for the run, a binary's for its `target` scope, a test's for its `test`.
struct CargoCoverage {
    static let uploadVariable = "TUIST_COVERAGE_UPLOAD"
    static let directoryVariable = "TUIST_CARGO_COVERAGE_DIR"
    static let nextRunnerVariable = "TUIST_CARGO_COVERAGE_NEXT"
    static let flag = ["-C", "instrument-coverage"]

    let directory: URL
    let profdata: String
    let cov: String
    let toolVersion: String
    let platform: String
    /// Whether each test process is recorded, which is what attributes profiles to binaries and tests.
    let attributes: Bool

    /// `tuist.toml`'s `[test_insights.coverage] upload`, unless `TUIST_COVERAGE_UPLOAD` says otherwise.
    static func requested(upload: Bool, environment: [String: String]) -> Bool {
        guard let value = environment[uploadVariable] else { return upload }
        return ["1", "true", "yes"].contains(value.lowercased())
    }

    /// The commands whose test binaries coverage instruments: those that run tests, and the archive build their
    /// shards run.
    static func instruments(_ invocation: CargoInvocation) -> Bool {
        invocation.executesTests || invocation.isNextestRun || invocation.command == "test-build"
    }

    /// Instruments the build and, for a command that runs tests, prepares their recording. Without the LLVM tools
    /// the run warns and goes on without coverage. `hooked` says Tuist's compiler hook sees every compilation, so it
    /// instruments only the repository's crates (`instruments(_:environment:)`); otherwise `RUSTFLAGS` instrument
    /// them all.
    static func prepare(
        invocation: CargoInvocation,
        environment: [String: String],
        directory: AbsolutePath,
        root: URL,
        cacheDirectory: URL?,
        hooked: Bool,
        process: CargoProcess
    ) async -> (coverage: CargoCoverage?, environment: [String: String]) {
        let rustc = environment["RUSTC"] ?? "rustc"
        guard let version = try? await process.capture(rustc, arguments: ["-vV"], environment: environment, directory: directory),
              let sysroot = try? await process.capture(
                  rustc, arguments: ["--print", "sysroot"], environment: environment, directory: directory
              ).trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            AlertController.current.warning(.alert("Code coverage is off for this run: rustc could not be queried."))
            return (nil, environment)
        }
        let fields = Dictionary(
            version.split(separator: "\n").compactMap { line -> (String, String)? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard let host = fields["host"] else { return (nil, environment) }
        let bin = URL(fileURLWithPath: sysroot).appendingPathComponent("lib/rustlib/\(host)/bin")
        let profdata = bin.appendingPathComponent("llvm-profdata").path
        let cov = bin.appendingPathComponent("llvm-cov").path
        func present() -> Bool {
            FileManager.default.isExecutableFile(atPath: profdata) && FileManager.default.isExecutableFile(atPath: cov)
        }
        // A rustup toolchain gets the component it lacks, as `cargo llvm-cov` offers to.
        if !present(), sysroot.contains("/toolchains/") {
            _ = try? await process.capture(
                "rustup", arguments: ["component", "add", "llvm-tools"], environment: environment, directory: directory
            )
        }
        guard present() else {
            AlertController.current.warning(.alert(
                "Code coverage is off for this run: it needs the LLVM tools of the Rust toolchain. Install them with 'rustup component add llvm-tools'."
            ))
            return (nil, environment)
        }
        var environment = environment
        if hooked {
            let repository = try? await process.capture(
                "git", arguments: ["rev-parse", "--show-toplevel"], environment: environment, directory: directory
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            environment[rootVariable] = repository.flatMap { $0.isEmpty ? nil : $0 } ?? directory.pathString
        } else {
            environment = instrumented(environment)
        }
        let coverageDirectory = root.appendingPathComponent("coverage")
        do {
            // `extract` holds a shard's archive, which nextest only extracts into an existing directory.
            for child in ["processes", "other", "extract"] {
                try FileManager.default.createDirectory(
                    at: coverageDirectory.appendingPathComponent(child), withIntermediateDirectories: true
                )
            }
        } catch {
            AlertController.current.warning(.alert("Code coverage is off for this run: \(error.localizedDescription)"))
            return (nil, environment)
        }
        // Profiles of processes no runner started, such as build scripts and an archive's listing, stay out of
        // the working directory.
        environment["LLVM_PROFILE_FILE"] = coverageDirectory.appendingPathComponent("other/%p-%m.profraw").path
        // A shard archive's build runs no tests of its own; its shards collect the coverage.
        guard invocation.command != "test-build" else { return (nil, environment) }
        environment[directoryVariable] = coverageDirectory.path

        let triple = target(invocation.arguments) ?? host
        let runnerVariable = "CARGO_TARGET_\(triple.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.map(String.init).joined())_RUNNER"
        var attributes = false
        if !CargoConfiguration.definesRunner(
            directory: URL(fileURLWithPath: directory.pathString), arguments: invocation.arguments, environment: environment
        ), let script = try? installRunner(in: cacheDirectory ?? root) {
            environment[nextRunnerVariable] = environment[runnerVariable]
            environment[runnerVariable] = script.path
            attributes = true
        } else if environment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError.write(Data(
                "Tuist Cargo coverage: a configured target runner keeps tests from being recorded; only the run's coverage is collected.\n"
                    .utf8
            ))
        }
        return (
            CargoCoverage(
                directory: coverageDirectory,
                profdata: profdata,
                cov: cov,
                toolVersion: "rustc \(fields["release"] ?? "")/LLVM \(fields["LLVM version"] ?? "")",
                platform: triple,
                attributes: attributes
            ),
            environment
        )
    }

    /// Adds `-C instrument-coverage` to the flags Cargo will use: `CARGO_ENCODED_RUSTFLAGS` or `RUSTFLAGS` when set,
    /// since they replace every configured flag, and otherwise `build.rustflags`, whose environment value Cargo adds
    /// to the configuration files'. Target-specific `rustflags` in a configuration file take precedence over
    /// `build.rustflags`; such a project sets the flag itself.
    static func instrumented(_ environment: [String: String]) -> [String: String] {
        var environment = environment
        func adding(_ flags: [String]) -> [String]? {
            zip(flags, flags.dropFirst()).contains { $0 == "-C" && $1 == "instrument-coverage" }
                || flags.contains("-Cinstrument-coverage") ? nil : flags + flag
        }
        if let encoded = environment["CARGO_ENCODED_RUSTFLAGS"] {
            let flags = encoded.isEmpty ? [] : encoded.components(separatedBy: "\u{1F}")
            if let flags = adding(flags) { environment["CARGO_ENCODED_RUSTFLAGS"] = flags.joined(separator: "\u{1F}") }
        } else if let rustflags = environment["RUSTFLAGS"] {
            if let flags = adding(rustflags.split(separator: " ").map(String.init)) {
                environment["RUSTFLAGS"] = flags.joined(separator: " ")
            }
        } else {
            let flags = environment["CARGO_BUILD_RUSTFLAGS"]?.split(separator: " ").map(String.init) ?? []
            if let flags = adding(flags) { environment["CARGO_BUILD_RUSTFLAGS"] = flags.joined(separator: " ") }
        }
        return environment
    }

    private static func target(_ arguments: [String]) -> String? {
        let options = Array(arguments.prefix { $0 != "--" })
        let targets = options.enumerated().compactMap { index, option -> String? in
            if option == "--target", index + 1 < options.count { return options[index + 1] }
            return option.hasPrefix("--target=") ? String(option.dropFirst(9)) : nil
        }
        return targets.count == 1 ? targets[0] : nil
    }

    /// Records each test process's arguments in `$TUIST_CARGO_COVERAGE_DIR/processes/<id>` and writes its profile
    /// beside it. The script has a stable path, so the runner Cargo sees, and keys compilations with, stays the
    /// same from one run to the next.
    static let runnerScript = """
    #!/bin/sh
    # Tuist: records each test process for code coverage, then runs it.
    dir="${TUIST_CARGO_COVERAGE_DIR:-}"
    if [ -n "$dir" ] && record=$(mktemp "$dir/processes/XXXXXXXX" 2>/dev/null); then
        printf '%s\\000' "$@" > "$record"
        LLVM_PROFILE_FILE="$record-%p-%m.profraw"
        export LLVM_PROFILE_FILE
    fi
    if [ -n "${TUIST_CARGO_COVERAGE_NEXT:-}" ]; then
        exec $TUIST_CARGO_COVERAGE_NEXT "$@"
    fi
    exec "$@"

    """

    static func installRunner(in directory: URL) throws -> URL {
        let script = directory.appendingPathComponent("tuist-coverage-runner-v1")
        if (try? String(contentsOf: script, encoding: .utf8)) != runnerScript {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent(".tuist-coverage-runner-\(UUID().uuidString)")
            try runnerScript.write(to: staging, atomically: false, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
            if rename(staging.path, script.path) != 0 {
                try? FileManager.default.removeItem(at: staging)
                throw CocoaError(.fileWriteUnknown)
            }
        }
        return script
    }
}

// MARK: - Completion

extension CargoCoverage {
    /// `tuist cargo coverage-complete [--commit <sha>]`: tells the server that every run gathering coverage for the
    /// commit has reported, as `tuist coverage complete` does, which the Linux CLI doesn't have. The commit defaults
    /// to the checkout's, or the one the CI provider reports.
    static func complete(arguments: [String], environment: [String: String], directory: AbsolutePath) async throws {
        let config = try? await ConfigLoader().loadCargoConfig(path: directory)
        guard let handle = environment["TUIST_PROJECT"] ?? config?.fullHandle else {
            throw CargoReportError(message: "Configure a project in tuist.toml or TUIST_PROJECT to complete a commit's coverage.")
        }
        guard let serverURL = URL(string: environment["TUIST_URL"] ?? config?.url.absoluteString ?? "https://tuist.dev"),
              ["https", "http"].contains(serverURL.scheme ?? "")
        else { throw CargoReportError(message: "Invalid Tuist server URL.") }
        let option = arguments.firstIndex(of: "--commit").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            ?? arguments.first { $0.hasPrefix("--commit=") }.map { String($0.dropFirst(9)) }
        var commit = option
        if commit == nil { commit = try? await GitController().gitInfo(workingDirectory: directory).sha }
        guard let commit, !commit.isEmpty else {
            throw CargoReportError(
                message: "Pass --commit, or run it from a Git checkout, to name the commit whose coverage is complete."
            )
        }
        let completion = try await CompleteCommitCoverageService().completeCommitCoverage(
            fullHandle: handle, serverURL: serverURL, gitCommitSHA: commit
        )
        let message = switch completion {
        case let .complete(coverage):
            "Coverage of commit \(coverage.gitCommitSHA.prefix(7)) is complete: \(coverage.coverage)%."
                + (coverage.incomplete ? " The figure is incomplete, so the actual coverage may be higher." : "")
        case .pending:
            "No run of commit \(commit.prefix(7)) has reported coverage yet. Its coverage is marked complete once one does."
        }
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}

// MARK: - What the run left out

extension CargoCoverage {
    private static let cargoValues: Set<String> = [
        "--features", "-F", "--target", "--target-dir", "--profile", "-j", "--jobs", "--manifest-path", "--config",
        "--color", "--message-format", "--lockfile-path", "-Z", "--artifact-dir", "--cargo-profile", "--test-threads",
        "--retries", "--failure-output", "--success-output", "--status-level", "--final-status-level", "--max-fail",
        "--archive-file", "--workspace-remap", "--tool-config-file", "--no-tests", "--extract-to",
        "--message-format-version", "--cargo-message-format", "--show-progress", "--timings",
    ]
    private static let selectingValues: Set<String> = [
        "-p", "--package", "--exclude", "--test", "--bin", "--example", "--bench", "-E", "--filterset", "--partition",
    ]
    private static let selectingFlags: Set<String> = ["--lib", "--bins", "--tests", "--examples", "--benches", "--doc"]
    private static let harnessValues: Set<String> = ["--test-threads", "--logfile", "--format", "--color", "-Z", "--shuffle-seed"]

    /// Whether the caller's arguments limit the run to the tests they select: test name filters, `--skip`,
    /// `--ignored`, packages, targets, nextest filtersets or partitions. Such a run names the tests it ran.
    /// Tuist's own selections, a shard's share and quarantine, are not the caller's.
    static func narrowed(_ arguments: [String]) -> Bool {
        let invocation = CargoInvocation(arguments)
        guard let command = invocation.commandIndex else { return false }
        var index = command + (invocation.isNextestRun ? 2 : 1)
        var harness = false
        while index < arguments.count {
            let argument = arguments[index]
            let key = argument.components(separatedBy: "=")[0]
            let inline = argument.contains("=")
            if argument == "--" {
                harness = true
            } else if !harness {
                if selectingFlags.contains(argument) || selectingValues.contains(key) { return true }
                if argument.hasPrefix("-p"), argument.count > 2, !argument.hasPrefix("--") { return true }
                if key == "--run-ignored" {
                    let value = inline ? argument.components(separatedBy: "=")[1]
                        : index + 1 < arguments.count ? arguments[index + 1] : ""
                    if value == "only" { return true }
                    index += inline ? 1 : 2
                    continue
                }
                if cargoValues.contains(key) {
                    index += inline ? 1 : 2
                    continue
                }
                if !argument.hasPrefix("-") { return true }
            } else {
                if key == "--skip" || key == "--ignored" { return true }
                if harnessValues.contains(key) {
                    index += inline ? 1 : 2
                    continue
                }
                if !argument.hasPrefix("-") { return true }
            }
            index += 1
        }
        return false
    }

    /// Whether the run left tests out: its caller narrowed it, or a failure stopped it before every test binary,
    /// or under nextest every test, ran. A shard's share and quarantined tests are not left out.
    static func partial(_ arguments: [String], failed: Bool) -> Bool {
        let options = arguments.prefix { $0 != "--" }
        let failFast = !options.contains("--no-fail-fast") && !options.contains("--max-fail=all")
            && !zip(options, options.dropFirst()).contains { $0 == "--max-fail" && $1 == "all" }
        return narrowed(arguments) || (failed && failFast)
    }

    /// `Module/Suite/test`, with a `/` or `%` inside a part percent-encoded: Cargo modules such as
    /// `app::bin/tool` and doctest names hold one.
    static func identifier(module: String, suite: String, name: String) -> String {
        [module, suite, name].map { part in
            part.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
        }.joined(separator: "/")
    }
}

// MARK: - Collection

extension CargoCoverage {
    struct Process: Equatable {
        let binary: String
        let module: String
        /// The test the process ran on its own (nextest's `--exact <name>`), nil for a whole binary.
        let test: String?
        let profiles: [URL]
    }

    struct Package {
        let name: String
        let directory: String
        let testSources: Set<String>
    }

    /// What the collector hands the report: the `coverage` block's fields and, when processes were recorded,
    /// `coverage_evidence`.
    struct Result {
        var files: [[String: Any]]
        var partial: Bool
        var evidence: [String: Any]?
    }

    /// What a test run reports about coverage: whether it was set up to collect it, the tests a narrowed run ran,
    /// and what it measured.
    struct Report {
        var enabled: Bool
        var result: Result?
        var onlyTestIdentifiers: [String]?
        var toolVersion = ""
        var platform = ""
        var repositoryRoot = ""
    }

    /// Each file's blob as the checkout has it: the index's, or the working tree's for a file it changed.
    static func blobIDs(
        paths: [String], root: String, process: CargoProcess, environment: [String: String]
    ) async -> [String: String] {
        guard !paths.isEmpty, let directory = try? AbsolutePath(validating: root) else { return [:] }
        let wanted = Set(paths)
        func git(_ arguments: [String]) async -> [String] {
            (try? await process.capture("git", arguments: arguments, environment: environment, directory: directory))?
                .split(separator: "\0").map(String.init) ?? []
        }
        var blobs: [String: String] = [:]
        for entry in await git(["ls-files", "--stage", "-z"]) {
            let parts = entry.split(separator: "\t", maxSplits: 1).map(String.init)
            let meta = parts.first?.split(separator: " ").map(String.init) ?? []
            guard parts.count == 2, meta.count >= 2, meta[0] != "160000", wanted.contains(parts[1]) else { continue }
            blobs[parts[1]] = meta[1]
        }
        let changed = Set(await git(["diff", "--name-only", "--diff-filter=d", "-z"])
            + git(["ls-files", "--others", "--exclude-standard", "-z"])).intersection(wanted).sorted()
        for start in stride(from: 0, to: changed.count, by: 500) {
            let batch = Array(changed[start ..< min(start + 500, changed.count)])
            let output = (try? await process.capture(
                "git", arguments: ["hash-object", "--"] + batch, environment: environment, directory: directory
            ))?.split(separator: "\n").map(String.init) ?? []
            for (path, blob) in zip(batch, output) where output.count == batch.count {
                blobs[path] = blob
            }
        }
        return blobs
    }

    /// The processes the runner recorded, matched to the test binaries the run reported (`binaries`, by path, to
    /// their module). Listing processes (`--list`) and binaries the run didn't report, such as doctests, are left out.
    static func processes(in directory: URL, binaries: [String: String]) -> [Process] {
        let modules = Dictionary(
            binaries.map { (URL(fileURLWithPath: $0.key).lastPathComponent, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        let folder = directory.appendingPathComponent("processes")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let profiles = Dictionary(grouping: entries.filter { $0.hasSuffix(".profraw") }) {
            String($0.prefix { $0 != "-" })
        }
        return entries.filter { !$0.contains("-") && !$0.hasPrefix(".") }.sorted().compactMap { record in
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(record).path),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            let arguments = text.split(separator: "\0", omittingEmptySubsequences: false).map(String.init).dropLast()
            guard let binary = arguments.first, !arguments.contains("--list"),
                  let module = modules[URL(fileURLWithPath: binary).lastPathComponent]
            else { return nil }
            let exact = arguments.firstIndex(of: "--exact").flatMap { arguments.index(after: $0) < arguments.endIndex
                ? arguments[arguments.index(after: $0)] : nil
            }
            let files = (profiles[record] ?? []).sorted().map { folder.appendingPathComponent($0) }
            return Process(binary: binary, module: module, test: exact, profiles: files)
        }
    }

    /// Reads the run's coverage. `binaries` are the test binaries the run reported, by path, to their module;
    /// `tests` the tests it reported, as `(module, suite, name)`, which plain `cargo test` reports as overlapping
    /// each other in their binary's process.
    func collect(
        binaries: [String: String],
        tests: [(module: String, suite: String, name: String)],
        packages: [Package],
        workspaceRoot: String,
        repositoryRoot: String,
        workingDirectory: String,
        remaps: [(from: String, to: String)] = [],
        partial: Bool
    ) async -> Result? {
        let processes = Self.processes(in: directory, binaries: binaries)
        let work = directory.appendingPathComponent("work")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        // Without recorded processes, the run's profiles are all there is; the binaries are the ones it reported.
        let objects = attributes ? Array(Set(processes.map(\.binary))).sorted()
            : binaries.keys.filter { FileManager.default.fileExists(atPath: $0) }.sorted()
        let runProfiles = attributes ? processes.flatMap(\.profiles) : Self
            .profiles(in: directory.appendingPathComponent("other"))
        guard !objects.isEmpty, !runProfiles.isEmpty else {
            if !binaries.isEmpty {
                AlertController.current.warning(.alert(
                    "The tests wrote no coverage profiles. A configuration file's target-specific rustflags replace Tuist's '-C instrument-coverage'; add it to them."
                ))
            }
            return nil
        }
        let resolver = Resolver(
            packages: packages, workspaceRoot: workspaceRoot, repositoryRoot: repositoryRoot,
            workingDirectory: workingDirectory, remaps: remaps
        )
        guard let report = await export(
            profiles: runProfiles, objects: objects, functions: true, name: "run", work: work
        ) else { return nil }
        let files = Self.files(report, resolver: resolver)
        if files.isEmpty, !report.isEmpty {
            AlertController.current.warning(.alert(
                "The run's code coverage named no file of this repository, so none was uploaded. It measured \(report.keys.sorted().prefix(3).joined(separator: ", "))."
            ))
        }

        guard attributes else { return Result(files: files, partial: partial, evidence: nil) }
        let evidence = await evidence(processes: processes, tests: tests, resolver: resolver, work: work)
        return Result(files: files, partial: partial, evidence: evidence)
    }

    private static func profiles(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".profraw") }.sorted().map { directory.appendingPathComponent($0) }
    }

    /// The `target` scope of each binary and, for processes that ran one test, the `test` scope of each test,
    /// the lines of each read on their own. A test retried in several processes gets the union of its attempts.
    private func evidence(
        processes: [Process],
        tests: [(module: String, suite: String, name: String)],
        resolver: Resolver,
        work: URL
    ) async -> [String: Any] {
        struct Unit: Hashable {
            let module: String
            let test: String?
        }
        var units: [Unit: (binary: String, profiles: [URL])] = [:]
        for process in processes where !process.profiles.isEmpty {
            for unit in [Unit(module: process.module, test: nil)] +
                (process.test.map { [Unit(module: process.module, test: $0)] } ?? [])
            {
                units[unit, default: (process.binary, [])].profiles += process.profiles
            }
        }
        let ordered = units.keys.sorted { ($0.module, $0.test ?? "") < ($1.module, $1.test ?? "") }
        var reports: [Unit: [String: [Int: Int]]] = [:]
        var failed = false
        await withTaskGroup(of: (Unit, [String: [Int: Int]]?).self) { group in
            var next = ordered.enumerated().makeIterator()
            func add() {
                guard let item = next.next(), let entry = units[item.element] else { return }
                let unit = item.element
                let name = "unit-\(item.offset)"
                group.addTask {
                    let report = await self.export(
                        profiles: entry.profiles, objects: [entry.binary], functions: false, name: name, work: work
                    )
                    return (unit, report.map { $0.mapValues(\.lines) })
                }
            }
            for _ in 0 ..< max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)) {
                add()
            }
            for await (unit, report) in group {
                if let report { reports[unit] = report } else { failed = true }
                add()
            }
        }
        var paths: [String] = []
        var indices: [String: Int] = [:]
        var scopes: [[String: Any]] = []
        for unit in ordered {
            guard let report = reports[unit] else { continue }
            var files: [Int] = []
            var lines: [[Int]] = []
            for (source, counts) in report.sorted(by: { $0.key < $1.key }) {
                guard let path = resolver.repositoryPath(source)?.path else { continue }
                let executed = counts.filter { $0.value > 0 }.keys.sorted()
                guard !executed.isEmpty else { continue }
                let index = indices[path] ?? {
                    paths.append(path)
                    indices[path] = paths.count - 1
                    return paths.count - 1
                }()
                files.append(index)
                lines.append(Self.ranges(executed))
            }
            guard !files.isEmpty else { continue }
            let identity = unit.test.map(NextestReport.identity) ?? (suite: "", name: "")
            scopes.append([
                "kind": unit.test == nil ? "target" : "test", "module": unit.module, "suite": identity.suite,
                "name": identity.name, "files": files, "lines": lines,
            ])
        }
        // A binary whose tests shared its process: nothing could be attributed to any one of them.
        let recordedTests = Set(processes.filter { $0.test != nil }.map(\.module))
        let shared = Set(processes.filter { $0.test == nil }.map(\.module)).subtracting(recordedTests)
        let overlapped: [[String: Any]] = tests.filter { shared.contains($0.module) }
            .map { ["module": $0.module, "suite": $0.suite, "name": $0.name] }
        var evidence: [String: Any] = [
            "paths": paths, "scopes": scopes, "status": failed && scopes.isEmpty ? "failed" : "collected",
        ]
        if !overlapped.isEmpty { evidence["overlapped_tests"] = overlapped }
        return evidence
    }

    /// Flattened inclusive ranges of sorted line numbers: `[3, 5, 9, 9]` is lines 3 to 5 and line 9.
    static func ranges(_ lines: [Int]) -> [Int] {
        var result: [Int] = []
        for line in lines {
            if let last = result.last, last + 1 == line {
                result[result.count - 1] = line
            } else {
                result += [line, line]
            }
        }
        return result
    }

    /// Merges the profiles and exports them over the objects as LCOV, by source file.
    private func export(
        profiles: [URL], objects: [String], functions: Bool, name: String, work: URL
    ) async -> [String: LCOVFile]? {
        let inputs = work.appendingPathComponent("\(name).inputs")
        let merged = work.appendingPathComponent("\(name).profdata")
        let output = work.appendingPathComponent("\(name).lcov")
        defer {
            for file in [inputs, merged, output] {
                try? FileManager.default.removeItem(at: file)
            }
        }
        guard (try? profiles.map(\.path).joined(separator: "\n").write(to: inputs, atomically: false, encoding: .utf8)) != nil,
              Self.run(profdata, ["merge", "-sparse", "--failure-mode=all", "-f", inputs.path, "-o", merged.path]),
              Self.run(
                  cov,
                  ["export", "-format=lcov", "-skip-branches"] + (functions ? [] : ["-skip-functions"])
                      + ["-instr-profile", merged.path, objects[0]] + objects.dropFirst().flatMap { ["-object", $0] },
                  output: output
              ),
              let handle = try? FileHandle(forReadingFrom: output)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd() else { return nil }
        return LCOVFile.parse(data)
    }

    private static func run(_ executable: String, _ arguments: [String], output: URL? = nil) -> Bool {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: output) else { return false }
            process.standardOutput = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }
}

// MARK: - Report

extension CargoCoverage {
    /// One source file of an LCOV export: each executable line's count and each function's start and count.
    struct LCOVFile: Equatable {
        var lines: [Int: Int] = [:]
        var functions: [(name: String, line: Int)] = []
        var calls: [String: Int] = [:]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.lines == rhs.lines && lhs.calls == rhs.calls
                && lhs.functions.map(\.name) == rhs.functions.map(\.name) && lhs.functions.map(\.line) == rhs.functions
                .map(\.line)
        }

        static func parse(_ data: Data) -> [String: LCOVFile] {
            var files: [String: LCOVFile] = [:]
            var path: String?
            var file = LCOVFile()
            func count(_ value: Substring) -> Int { Int(min(UInt64(value) ?? 0, UInt64(Int32.max))) }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if line.hasPrefix("SF:") {
                    path = String(line.dropFirst(3))
                    file = files[path!] ?? LCOVFile()
                } else if line == "end_of_record" {
                    if let path { files[path] = file }
                    path = nil
                } else if line.hasPrefix("DA:") {
                    let parts = line.dropFirst(3).split(separator: ",")
                    guard parts.count >= 2, let number = Int(parts[0]) else { continue }
                    file.lines[number, default: 0] += count(parts[1])
                } else if line.hasPrefix("FN:") {
                    let parts = line.dropFirst(3).split(separator: ",", maxSplits: 1)
                    guard parts.count == 2, let number = Int(parts[0]) else { continue }
                    file.functions.append((String(parts[1]), number))
                } else if line.hasPrefix("FNDA:") {
                    let parts = line.dropFirst(5).split(separator: ",", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    file.calls[String(parts[1]), default: 0] += count(parts[0])
                }
            }
            return files
        }
    }

    /// Where the run's source files are: compilations remap the workspace to relative paths when the compilation
    /// cache runs, so a relative path is the workspace's, else the working directory's.
    struct Resolver {
        let packages: [Package]
        let workspaceRoot: String
        let repositoryRoot: String
        let workingDirectory: String
        /// Roots the binaries' sources were built under and where they are in this checkout, longest first: a
        /// nextest archive built in another checkout names that checkout's paths.
        let remaps: [(from: String, to: String)]

        init(
            packages: [Package], workspaceRoot: String, repositoryRoot: String, workingDirectory: String,
            remaps: [(from: String, to: String)] = []
        ) {
            self.packages = packages.map {
                Package(
                    name: $0.name, directory: Self.canonical($0.directory),
                    testSources: Set($0.testSources.map(Self.canonical))
                )
            }.sorted { $0.directory.count > $1.directory.count }
            self.workspaceRoot = workspaceRoot
            self.repositoryRoot = Self.canonical(repositoryRoot)
            self.workingDirectory = workingDirectory
            // Both spellings of a root, since the build machine's may not exist here to resolve (`/tmp` and
            // `/private/tmp` on macOS).
            self.remaps = remaps.flatMap { remap in
                Set([remap.from, Self.canonical(remap.from)]).map { (from: $0, to: remap.to) }
            }.sorted { $0.from.count > $1.from.count }
        }

        static func canonical(_ path: String) -> String {
            URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        }

        /// The file's path relative to the repository, and its absolute path, or nil outside it.
        func repositoryPath(_ source: String) -> (path: String, absolute: String)? {
            let remapped = remaps.first { source.hasPrefix($0.from + "/") }
                .map { $0.to + source.dropFirst($0.from.count) } ?? source
            let candidates = remapped.hasPrefix("/") ? [remapped]
                : [workspaceRoot + "/" + source, workingDirectory + "/" + source]
            for candidate in candidates {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue
                else { continue }
                let absolute = Self.canonical(candidate)
                guard absolute.hasPrefix(repositoryRoot + "/") else { return nil }
                return (String(absolute.dropFirst(repositoryRoot.count + 1)), absolute)
            }
            return nil
        }

        func package(of absolute: String) -> Package? {
            packages.first { absolute.hasPrefix($0.directory + "/") }
        }

        /// Integration tests, benchmarks and examples, by their directory or by the source their target names.
        func isTest(_ absolute: String) -> Bool {
            guard let package = package(of: absolute) else { return false }
            return package.testSources.contains(absolute)
                || ["tests", "benches", "examples"].contains { absolute.hasPrefix("\(package.directory)/\($0)/") }
        }
    }

    /// The `coverage` block's files: one per repository source file, with the package it belongs to and whether it
    /// is test code, its lines' counts and its functions. Each executable line belongs to the function that starts
    /// closest above it; a generic function's instantiations and a function compiled into several binaries count as
    /// one. Test code keeps its counts but not its lines.
    static func files(_ report: [String: LCOVFile], resolver: Resolver) -> [[String: Any]] {
        var merged: [String: (absolute: String, file: LCOVFile)] = [:]
        for (source, file) in report {
            guard let resolved = resolver.repositoryPath(source) else { continue }
            let path = resolved.path
            var entry = merged[path] ?? (resolved.absolute, LCOVFile())
            entry.file.lines.merge(file.lines, uniquingKeysWith: +)
            entry.file.functions += file.functions
            entry.file.calls.merge(file.calls, uniquingKeysWith: +)
            merged[path] = entry
        }
        return merged.sorted { $0.key < $1.key }.map { path, entry in
            let isTest = resolver.isTest(entry.absolute)
            let lines = entry.file.lines.sorted { $0.key < $1.key }
            let file: [String: Any] = [
                "path": path,
                "targets": resolver.package(of: entry.absolute).map { [$0.name] } ?? [],
                "is_test": isTest,
                "covered_lines": lines.filter { $0.value > 0 }.count,
                "executable_lines": lines.count,
                "line_numbers": isTest ? [] : lines.map(\.key),
                "execution_counts": isTest ? [] : lines.map(\.value),
                "functions": isTest ? [] : functions(entry.file),
            ]
            return file
        }
    }

    static func functions(_ file: LCOVFile) -> [[String: Any]] {
        var byName: [String: (line: Int, calls: Int)] = [:]
        for function in file.functions {
            let name = CargoSymbol.function(function.name)
            let calls = file.calls[function.name] ?? 0
            let current = byName[name]
            byName[name] = (min(current?.line ?? function.line, function.line), (current?.calls ?? 0) + calls)
        }
        let starts = byName.map { (line: $0.value.line, name: $0.key) }.sorted { ($0.line, $0.name) < ($1.line, $1.name) }
        var owned: [String: [Int]] = [:]
        var index = -1
        for (line, count) in file.lines.sorted(by: { $0.key < $1.key }) {
            while index + 1 < starts.count, starts[index + 1].line <= line {
                index += 1
            }
            if index >= 0 { owned[starts[index].name, default: []].append(count) }
        }
        return starts.map { start in
            let counts = owned[start.name] ?? []
            return [
                "name": start.name,
                "line_number": start.line,
                "execution_count": byName[start.name]?.calls ?? 0,
                "covered_lines": counts.filter { $0 > 0 }.count,
                "executable_lines": counts.count,
            ]
        }
    }

    /// Raw DEFLATE, what the server inflates (`PublishCoverageWorker`): compressed where the platform has a
    /// compressor, and in stored blocks elsewhere.
    static func deflate(_ data: Data) -> Data {
        #if canImport(Compression)
            var compressed = Data()
            if let filter = try? OutputFilter(.compress, using: .zlib, writingTo: { compressed.append($0 ?? Data()) }),
               (try? filter.write(data)) != nil, (try? filter.finalize()) != nil
            {
                return compressed
            }
        #endif
        var output = Data()
        var offset = 0
        repeat {
            let length = min(65535, data.count - offset)
            let final: UInt8 = offset + length >= data.count ? 1 : 0
            output.append(final)
            output.append(contentsOf: [
                UInt8(length & 0xFF),
                UInt8(length >> 8),
                UInt8(~length & 0xFF),
                UInt8((~length >> 8) & 0xFF),
            ])
            output.append(data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + length))
            offset += length
        } while offset < data.count
        return output
    }
}

// MARK: - Variants

/// A run that collects coverage through Tuist's compiler hook instruments only the repository's own libraries,
/// binaries and test harnesses. Dependencies, build scripts and proc macros compile with the arguments they have without
/// coverage, so they share their outputs and every cache entry with ordinary builds. The flag the hook adds is
/// invisible to Cargo's fingerprints, so each instrumented crate's outputs carry a marker
/// (`<crate><suffix>.tuist-coverage` in their directory) and, before Cargo starts, `reconcile` swaps the repository's
/// crates built as the other variant for the ones kept aside, fingerprints included, for Cargo to judge.
extension CargoCoverage {
    /// The repository root whose crates the hook instruments, set by a run that collects coverage.
    static let rootVariable = "TUIST_CARGO_COVERAGE_ROOT"
    static let markerExtension = "tuist-coverage"

    /// Whether the hook instruments this rustc invocation, in a run collecting coverage: a library, binary or test
    /// harness of a crate in the repository and outside Cargo's home (registry and git checkouts). Build scripts and
    /// proc macros run during the build, not in the tests, so they compile as without coverage, like doctests, which
    /// link instrumented libraries too.
    static func instruments(_ arguments: [String], environment: [String: String]) -> Bool {
        guard let root = environment[rootVariable], let manifest = environment["CARGO_MANIFEST_DIR"],
              !arguments.contains(where: { $0.hasPrefix("--print") }),
              let name = CargoCacheInputs.values("--crate-name", in: arguments).first, !name.hasPrefix("build_script_"),
              CargoCacheInputs.values("--emit", in: arguments).first.map({ $0.split(separator: ",").contains("link") }) ?? true,
              arguments.contains("--test") || CargoCacheInputs.values("--crate-type", in: arguments)
              .allSatisfy({ ["lib", "rlib", "bin"].contains($0) })
        else { return false }
        return isRepository(manifest, root: root, cargoHome: cargoHome(environment))
    }

    /// `<out-dir>/<crate><extra-filename>.tuist-coverage`, beside the compilation's dep-info file.
    static func marker(_ arguments: [String]) -> URL? {
        guard let name = CargoCacheInputs.values("--crate-name", in: arguments).first,
              let output = CargoCacheInputs.values("--out-dir", in: arguments).first else { return nil }
        let suffix = CargoCacheInputs.values("-C", in: arguments).first { $0.hasPrefix("extra-filename=") }
            .map { String($0.dropFirst("extra-filename=".count)) } ?? ""
        return URL(fileURLWithPath: output).appendingPathComponent("\(name)\(suffix).\(markerExtension)")
    }

    /// The profile directory (`<target-dir>/[<triple>/]<profile>`) a command builds into. Cargo's metadata says where
    /// the target directory is, unless the caller already knows.
    static func profile(
        executable: String, arguments: [String], environment: [String: String], directory: AbsolutePath,
        targetDirectory: URL?, process: CargoProcess
    ) async -> URL? {
        var target = targetDirectory
        if target == nil {
            let options = Array(arguments.prefix { $0 != "--" })
            var metadata = ["metadata", "--format-version", "1", "--no-deps", "--offline"]
            for option in ["--manifest-path", "--target-dir"] {
                if let value = CargoCacheInputs.values(option, in: options).last { metadata += [option, value] }
            }
            target = (try? await process.capture(executable, arguments: metadata, environment: environment, directory: directory))
                .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { $0["target_directory"] as? String }.map { URL(fileURLWithPath: $0) }
        }
        guard var profile = target else { return nil }
        if let triple = triple(arguments, environment: environment, directory: directory) {
            profile.appendPathComponent(triple)
        }
        return profile.appendingPathComponent(profileName(arguments))
    }

    /// Before Cargo starts, swaps the repository's crates that are not this run's variant (`swap`). A run collecting
    /// coverage (`rootVariable` set) swaps those built without it; a linking command without coverage swaps the
    /// instrumented ones of the profiles earlier coverage runs of this repository used, whose binaries would otherwise
    /// write profiles wherever they run. Metadata-only units (`cargo check`, rust-analyzer) are never
    /// touched, and nothing waits for another Cargo holding a profile it would only clean.
    static func reconcile(
        arguments: [String], environment: [String: String], profile: URL?, cacheDirectory: URL?, directory: AbsolutePath
    ) {
        let registry = (cacheDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("tuist-cargo"))
            .appendingPathComponent("coverage-profiles")
        let cargoHome = cargoHome(environment)
        let triple = triple(arguments, environment: environment, directory: directory) ?? ""
        if let root = environment[rootVariable] {
            guard let profile else { return }
            if let entry = try? JSONEncoder().encode(["profile": profile.path, "root": root, "triple": triple]) {
                try? FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
                try? entry.write(to: registry.appendingPathComponent(fingerprint(profile.path)), options: .atomic)
            }
            swap(profile: profile, instrumented: true, root: root, cargoHome: cargoHome, wait: true)
            return
        }
        guard ["build", "b", "run", "r", "test", "t", "bench", "nextest", "test-build", "install"]
            .contains(CargoInvocation(arguments).command ?? ""),
            let entries = try? FileManager.default.contentsOfDirectory(atPath: registry.path)
        else { return }
        let here = canonical(directory.pathString)
        let name = profileName(arguments)
        for file in entries {
            let entry = registry.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: entry),
                  let fields = try? JSONDecoder().decode([String: String].self, from: data),
                  let path = fields["profile"], let root = fields["root"]
            else { try? FileManager.default.removeItem(at: entry); continue }
            let profile = URL(fileURLWithPath: path)
            let repository = canonical(root)
            guard here == repository || here.hasPrefix(repository + "/"), profile.lastPathComponent == name,
                  fields["triple"] ?? "" == triple
            else { continue }
            if swap(profile: profile, instrumented: false, root: root, cargoHome: cargoHome, wait: false) == 0 {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// Swaps the profile's units that are not the `instrumented` variant for the variant kept aside earlier, and
    /// returns how many instrumented units remain. A unit moves with its Cargo fingerprint, so Cargo judges the variant
    /// moved back as it judged it when it was built: a source edited or a dependency rebuilt since makes it rebuild it.
    /// Units are read from their dep-info files: in `deps` and `examples`, with their fingerprint in
    /// `.fingerprint/<package>-<hash>`, or, in Cargo's build-directory layout since 1.100, the whole of
    /// `build/<package>/<hash>`, whose `out` holds `<crate>-<hash>.d` (which leaves out what build scripts write to their
    /// `OUT_DIR`). Building with coverage, a unit is the plain variant of a repository crate when it links code, is no
    /// build script, has no marker, and its first source is the repository's (Cargo names workspace members' sources
    /// relative to the workspace); building without it, every unit with a marker is the instrumented variant. A unit
    /// whose fingerprint is not found is deleted instead, so Cargo rebuilds it.
    @discardableResult
    static func swap(profile: URL, instrumented: Bool, root: String, cargoHome: String, wait: Bool) -> Int {
        let fileManager = FileManager.default
        var directories: [(URL, hash: String?)] = ["deps", "examples"].map { (profile.appendingPathComponent($0), nil) }
        let build = profile.appendingPathComponent("build")
        for package in (try? fileManager.contentsOfDirectory(atPath: build.path)) ?? [] {
            for hash in (try? fileManager.contentsOfDirectory(atPath: build.appendingPathComponent(package).path)) ?? [] {
                directories.append((build.appendingPathComponent("\(package)/\(hash)/out"), hash))
            }
        }
        let listings = directories.compactMap { directory, hash in
            (try? fileManager.contentsOfDirectory(atPath: directory.path)).map { (directory, hash, $0) }
        }.filter { !$0.2.isEmpty }
        let stash = profile.appendingPathComponent(".tuist-coverage")
        let away = stash.appendingPathComponent(instrumented ? "plain" : "coverage")
        let back = stash.appendingPathComponent(instrumented ? "coverage" : "plain")
        guard !listings.isEmpty || fileManager.fileExists(atPath: back.path) else { return 0 }
        // Cargo 1.99 and later hold `.cargo-build-lock` while they build; earlier versions `.cargo-lock`.
        let held = [".cargo-build-lock", ".cargo-lock"].map { profile.appendingPathComponent($0).path }
            .first { fileManager.fileExists(atPath: $0) } ?? profile.appendingPathComponent(".cargo-lock").path
        let lock = open(held, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard lock >= 0 else { return 1 }
        defer { close(lock) }
        guard flock(lock, wait ? LOCK_EX : LOCK_EX | LOCK_NB) == 0 else { return 1 }
        let fingerprints = Dictionary(
            ((try? fileManager.contentsOfDirectory(atPath: profile.appendingPathComponent(".fingerprint").path)) ?? [])
                .map { (String($0.split(separator: "-").last ?? ""), ".fingerprint/\($0)") },
            uniquingKeysWith: { first, _ in first }
        )
        var remaining = 0
        for (directory, hash, names) in listings {
            let markers = Set(names.filter { $0.hasSuffix(".\(markerExtension)") })
            remaining += markers.count
            for name in names where name.hasSuffix(".d") {
                let stem = String(name.dropLast(2))
                let marker = "\(stem).\(markerExtension)"
                guard markers.contains(marker) != instrumented, !stem.hasPrefix("build_script_"),
                      hash.map({ stem.hasSuffix("-" + $0) }) ?? true,
                      let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
                else { continue }
                let (outputs, sources) = depInfo(text)
                if instrumented {
                    let extensions = outputs.map { URL(fileURLWithPath: $0).pathExtension }
                    guard extensions.contains(where: { ["rlib", ""].contains($0) }),
                          !extensions.contains(where: { ["dylib", "so", "dll", "a", "lib"].contains($0) }),
                          let source = sources.first,
                          !source.hasPrefix("/") || isRepository(source, root: root, cargoHome: cargoHome)
                    else { continue }
                }
                if markers.contains(marker) { remaining -= 1 }
                let unit = hash == nil ? directory.lastPathComponent + "/" + stem
                    : String(directory.deletingLastPathComponent().path.dropFirst(profile.path.count + 1))
                // A fingerprint moves only with every output it vouches for, or Cargo would take the other variant's.
                let base = canonical(profile.path) + "/"
                let relative = (outputs + [directory.appendingPathComponent(marker).path]).map { path -> String? in
                    let path = canonical(path)
                    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
                }
                let paths: [String]? = if hash != nil {
                    [unit]
                } else if let fingerprint = fingerprints[String(stem.split(separator: "-").last ?? "")],
                          relative.allSatisfy({ $0 != nil })
                {
                    relative.compactMap { $0 } + [fingerprint]
                } else {
                    nil
                }
                guard let paths, move(paths, from: profile, to: away.appendingPathComponent(unit), record: true) else {
                    for output in outputs where !output.hasSuffix(".d") {
                        unlink(output)
                    }
                    unlink(directory.appendingPathComponent(marker).path)
                    continue
                }
            }
        }
        // The variant this build wants goes back where its slot is free; one Cargo rebuilt meanwhile is outdated.
        let kept = fileManager.enumerator(at: back, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.path }.filter { $0.hasSuffix("/.tuist-paths") } ?? []
        for list in kept {
            let unit = URL(fileURLWithPath: list).deletingLastPathComponent()
            if let paths = try? String(contentsOfFile: list, encoding: .utf8).split(separator: "\n").map(String.init),
               paths.allSatisfy({ !fileManager.fileExists(atPath: profile.appendingPathComponent($0).path) }),
               move(paths, from: unit, to: profile, record: false)
            {
                remaining += instrumented ? 1 : 0
            }
            try? fileManager.removeItem(at: unit)
        }
        return remaining
    }

    /// Moves the relative `paths` that exist from one directory to another. Moving into a stash (`record`) replaces
    /// what it held and lists them in its `.tuist-paths`. False when none exists or one cannot move.
    private static func move(_ paths: [String], from source: URL, to destination: URL, record: Bool) -> Bool {
        let fileManager = FileManager.default
        let present = paths.filter { fileManager.fileExists(atPath: source.appendingPathComponent($0).path) }
        guard !present.isEmpty else { return false }
        if record {
            try? fileManager.removeItem(at: destination)
            guard (try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)) != nil,
                  (try? Data(present.joined(separator: "\n").utf8).write(to: destination.appendingPathComponent(".tuist-paths")))
                  != nil
            else { return false }
        }
        for path in present {
            let target = destination.appendingPathComponent(path)
            try? fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard rename(source.appendingPathComponent(path).path, target.path) == 0 else { return false }
        }
        return true
    }

    /// The outputs a rustc dep-info file names (`<output>: <sources>`) and the sources of the first one.
    static func depInfo(_ text: String) -> (outputs: [String], sources: [String]) {
        func paths(_ text: Substring) -> [String] {
            var result: [String] = []
            var current = ""
            var escaped = false
            for character in text {
                if escaped {
                    current.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == " " {
                    if !current.isEmpty { result.append(current) }
                    current = ""
                } else {
                    current.append(character)
                }
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
        var outputs: [String] = []
        var sources: [String] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            guard let separator = line.range(of: ": ") else { continue }
            let inputs = paths(line[separator.upperBound...])
            guard !inputs.isEmpty, let output = paths(line[..<separator.lowerBound]).first else { continue }
            outputs.append(output)
            if sources.isEmpty { sources = inputs }
        }
        return (outputs, sources)
    }

    static func isRepository(_ path: String, root: String, cargoHome: String) -> Bool {
        let path = canonical(path)
        let root = canonical(root)
        return (path == root || path.hasPrefix(root + "/")) && !path.hasPrefix(canonical(cargoHome) + "/")
    }

    /// Symlinks resolved, and macOS's `/private` links spelled the same way whether or not the path exists.
    private static func canonical(_ path: String) -> String {
        CargoRelocation.canonical(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    private static func cargoHome(_ environment: [String: String]) -> String {
        environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo").path
    }

    private static func triple(_ arguments: [String], environment: [String: String], directory: AbsolutePath) -> String? {
        target(arguments) ?? environment["CARGO_BUILD_TARGET"].flatMap { $0.isEmpty ? nil : $0 }
            ?? CargoConfiguration.buildTarget(directory: URL(fileURLWithPath: directory.pathString), environment: environment)
    }

    /// The profile directory's name for a command's options, nextest's `--cargo-profile` included.
    private static func profileName(_ arguments: [String]) -> String {
        let options = Array(arguments.prefix { $0 != "--" })
        let kind = CargoInvocation(arguments).command == "bench" ? "bench" : "test"
        if let profile = CargoCacheInputs.values("--cargo-profile", in: options).last {
            return CargoUnitCache.profileDirectory(options: ["--profile", profile], kind: kind)
        }
        return CargoUnitCache.profileDirectory(options: options, kind: kind)
    }

    /// A stable file name for a path (FNV-1a), since the registry outlives the process.
    private static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
