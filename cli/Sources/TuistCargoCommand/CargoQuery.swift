import Foundation
import TuistREAPI

/// A read-only command a recorded run spawned, such as `git describe` from bat's `git_version!` or `xcrun
/// --show-sdk-path` from a build script. These run from protected programs the recorder cannot load into, so their
/// reads are unknown; what the run learned from one is its exit status and output, so the key holds those, from running
/// it again with the run's environment and working directory, like a Bazel workspace status command.
struct CargoQuery: Equatable {
    static let programs: Set<String> = ["git", "sw_vers", "uname", "xcode-select", "xcrun"]

    let program: String
    let directory: String
    /// How the command's environment differed from the run's: `NAME=VALUE` set, `-NAME` removed.
    let changes: [String]
    /// Including `argv[0]`.
    let arguments: [String]

    init(program: String, directory: String, changes: [String] = [], arguments: [String]) {
        self.program = program
        self.directory = directory
        self.changes = changes
        self.arguments = arguments
    }

    /// From a recorder `Q` event: the program that ran, the working directory, the environment changes and the
    /// arguments. `nil` unless the command only reads.
    init?(_ parts: [String]) {
        guard parts.count >= 4, Self.isQuery(program: parts[0], arguments: Array(parts.dropFirst(4))) else { return nil }
        self.init(program: parts[0], directory: parts[1], changes: Self.changes(parts[2]), arguments: Array(parts.dropFirst(3)))
    }

    static func changes(_ field: String) -> [String] {
        field.split(separator: "\u{1e}").map(String.init)
    }

    /// The run's environment with the command's changes applied.
    static func environment(_ base: [String: String], changes: [String]) -> [String: String] {
        var result = base
        for change in changes {
            if change.hasPrefix("-") {
                result[String(change.dropFirst())] = nil
            } else if let separator = change.firstIndex(of: "=") {
                result[String(change[..<separator])] = String(change[change.index(after: separator)...])
            }
        }
        return result
    }

    init?(relocated name: String, relocation: CargoRelocation) {
        guard let absolute = relocation.absolute(name) else { return nil }
        self.init(absolute.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init))
    }

    func relocated(_ relocation: CargoRelocation) -> String {
        relocation.relative(([program, directory, changes.joined(separator: "\u{1e}")] + arguments).joined(separator: "\u{1f}"))
    }

    /// Where a git query runs, after its `-C` options.
    var gitDirectory: String? {
        guard URL(fileURLWithPath: program).lastPathComponent == "git" else { return nil }
        var result = URL(fileURLWithPath: directory, isDirectory: true)
        var index = 1
        while index + 1 < arguments.count, arguments[index] == "-C" {
            result = URL(fileURLWithPath: arguments[index + 1], isDirectory: true, relativeTo: result)
            index += 2
        }
        return result.standardizedFileURL.path
    }

    private static func isQuery(program: String, arguments: [String]) -> Bool {
        switch URL(fileURLWithPath: program).lastPathComponent {
        case "sw_vers", "uname":
            return true
        case "xcode-select":
            return arguments == ["-p"] || arguments == ["--print-path"]
        case "xcrun":
            // `xcrun --sdk macosx --show-sdk-path`, `xcrun --find clang`; never a tool run through it.
            var index = 0
            var found = false
            while index < arguments.count {
                switch arguments[index] {
                case "--sdk", "-sdk", "--find", "-f", "--toolchain": index += 2
                case "--show-sdk-path", "--show-sdk-version", "--show-sdk-build-version", "--show-sdk-platform-path",
                     "--show-sdk-platform-version": index += 1
                default: return false
                }
                found = true
            }
            return found && index == arguments.count
        case "git":
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                if ["-C", "--git-dir", "--work-tree"].contains(argument) { index += 2; continue }
                if argument == "--no-pager" || argument == "--no-optional-locks" || argument.hasPrefix("--git-dir=")
                    || argument.hasPrefix("--work-tree=")
                { index += 1; continue }
                break
            }
            guard index < arguments.count,
                  [
                      "describe",
                      "rev-parse",
                      "rev-list",
                      "log",
                      "show",
                      "status",
                      "symbolic-ref",
                      "ls-files",
                      "name-rev",
                      "show-ref",
                      "diff",
                  ].contains(arguments[index])
            else { return false }
            return !arguments[index...].contains { $0.hasPrefix("--output") || $0 == "--ext-diff" || $0.hasPrefix("--exec") }
        default:
            return false
        }
    }

    /// The command's exit status and output now, relocated. Throws when it cannot run or does not finish in time.
    func output(environment: [String: String], relocation: CargoRelocation) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: program) else { return "missing" }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tuist-query-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let stdout = scratch.appendingPathComponent("stdout")
        let stderr = scratch.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = Self.environment(environment, changes: changes)
            .filter { !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("TUIST_CARGO_READ_") }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = try FileHandle(forWritingTo: stdout)
        process.standardError = try FileHandle(forWritingTo: stderr)
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            throw CargoCacheInvocation.CacheError.unsupported
        }
        let printed = [stdout, stderr].map { file -> String in
            let data = (try? Data(contentsOf: file)) ?? Data()
            return String(data: data, encoding: .utf8).map { "text:" + relocation.relative($0) } ?? "data:" + REAPI.digest(data)
                .hash
        }
        return REAPI.digest(Data(([String(process.terminationStatus)] + printed).joined(separator: "\u{0}").utf8)).hash
    }
}

/// A developer tool a recorded run spawned that only transforms files: ad hoc `codesign` of files the run wrote, a
/// single-file `swiftc` compilation, as mise's build script makes its macOS helpers, and `ar`/`ranlib`, as cc-rs
/// archives objects. They run from protected programs the recorder cannot load into, so their reads are modeled from
/// their arguments: files the run wrote are its own, other files they name are keyed like any recorded read, and the
/// tools and the SDK they use are keyed by the Xcode, SDK and OS builds. Anything else they could read (another flag, a
/// source outside the arguments) keeps the run uncacheable.
struct CargoTool: Equatable {
    static let programs: Set<String> = ["codesign", "swiftc", "ar", "ranlib"]

    let kind: String
    let program: String
    let directory: String
    let changes: String
    /// Source files the tool reads, which the run's key names like recorded reads.
    let inputs: [String]
    /// Files the tool writes, which are the run's own from then on.
    let outputs: [String]

    /// The key entry's name: what identifies the tool where it runs.
    var name: String { [kind, program, directory, changes].joined(separator: "\u{1f}") }

    /// From a recorder `Q` event (program, working directory, `argv`). `nil` unless every argument is understood and
    /// every file the tool writes is inside `writable`.
    /// `inheritsEnvironment` says the run handed it its own environment, which a compiler needs: its identity is
    /// taken from the run's.
    init?(_ parts: [String], writable: (String) -> Bool, written: (String) -> Bool) {
        guard parts.count >= 4 else { return nil }
        let directory = parts[1]
        let arguments = Array(parts.dropFirst(4))
        func path(_ value: String) -> String {
            CargoRelocation.canonical(value.hasPrefix("/") ? value : directory + "/" + value)
        }
        var inputs: [String] = []
        var outputs: [String] = []
        var index = 0
        switch URL(fileURLWithPath: parts[0]).lastPathComponent {
        case "codesign":
            guard parts[0] == "/usr/bin/codesign" else { return nil }
            var adHoc = false
            var targets = 0
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--force", "-f", "--deep", "--timestamp=none", "--generate-entitlement-der": index += 1
                case "--sign", "-s":
                    guard index + 1 < arguments.count, arguments[index + 1] == "-" else { return nil }
                    adHoc = true
                    index += 2
                case "--identifier", "-i", "--options", "-o":
                    guard index + 1 < arguments.count else { return nil }
                    index += 2
                default:
                    // Signing reads only the bundle it rewrites, which the run wrote.
                    guard !argument.hasPrefix("-"), writable(path(argument)), written(path(argument)) else { return nil }
                    targets += 1
                    index += 1
                }
            }
            guard adHoc, targets > 0 else { return nil }
            kind = "codesign"
        case "swiftc":
            var output = false
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "-O", "-Onone", "-Osize", "-g", "-gnone", "-parse-as-library", "-wmo", "-whole-module-optimization",
                     "-suppress-warnings", "-emit-executable":
                    index += 1
                case "-target", "-module-name":
                    guard index + 1 < arguments.count else { return nil }
                    index += 2
                case "-o":
                    guard index + 1 < arguments.count, writable(path(arguments[index + 1])) else { return nil }
                    outputs.append(path(arguments[index + 1]))
                    output = true
                    index += 2
                default:
                    guard !argument.hasPrefix("-"), argument.hasSuffix(".swift") else { return nil }
                    inputs.append(path(argument))
                    index += 1
                }
            }
            guard output, inputs.count == 1 else { return nil }
            kind = "swiftc"
        case "ar", "ranlib":
            let name = URL(fileURLWithPath: parts[0]).lastPathComponent
            guard parts[0] == "/usr/bin/" + name, !arguments.isEmpty else { return nil }
            var files = arguments[...]
            if name == "ar" {
                // Creating, replacing, appending and indexing: `cq`, `rcs`, `-s`; never extracting into the directory.
                let operations = files.removeFirst().drop { $0 == "-" }
                guard !operations.isEmpty, operations.allSatisfy({ "crqsuvDST".contains($0) }), !files.isEmpty else { return nil }
            } else {
                files = files.drop { $0 == "-s" || $0 == "-c" || $0 == "-no_warning_for_no_symbols" }
            }
            guard let archive = files.first, !archive.hasPrefix("-"), writable(path(archive)) else { return nil }
            outputs.append(path(archive))
            for member in files.dropFirst() {
                guard !member.hasPrefix("-") else { return nil }
                if !written(path(member)) { inputs.append(path(member)) }
            }
            kind = name
        default:
            return nil
        }
        self.inputs = inputs
        self.outputs = outputs
        program = parts[0]
        self.directory = directory
        changes = parts[2]
    }

    /// What the tool reads besides its arguments, by build: the OS for `codesign`; Xcode for the archivers; for
    /// `swiftc`, Xcode and its macOS SDK as well, and the compiler's own `--version` (the `xcrun` shim or a swiftly proxy
    /// select a toolchain from the environment and the working directory). The same builds on another machine compile,
    /// archive and sign alike.
    static func identity(_ name: String, environment: [String: String], relocation: CargoRelocation) throws -> String {
        let parts = name.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { throw CargoCacheInvocation.CacheError.unsupported }
        let os: String
        #if canImport(Darwin)
            var size = 0
            sysctlbyname("kern.osversion", nil, &size, nil, 0)
            var build = [CChar](repeating: 0, count: max(size, 1))
            guard size > 0, sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else {
                throw CargoCacheInvocation.CacheError.unsupported
            }
            os = String(cString: build)
        #else
            // These are Apple's tools, which only the macOS recorder models.
            throw CargoCacheInvocation.CacheError.unsupported
        #endif
        var values = [parts[0], "os=" + os]
        guard parts[0] != "codesign" else { return values.joined(separator: "\n") }
        let environment = CargoQuery.environment(environment, changes: CargoQuery.changes(parts[3]))
        guard environment["SDKROOT"] == nil,
              let developer = environment["DEVELOPER_DIR"]
              ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")),
              developer.hasSuffix("/Contents/Developer")
        else { throw CargoCacheInvocation.CacheError.unsupported }
        let xcode = URL(fileURLWithPath: developer).deletingLastPathComponent().appendingPathComponent("version.plist")
        let sdk = URL(fileURLWithPath: developer).appendingPathComponent(
            "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/CoreServices/SystemVersion.plist"
        )
        for (label, plist) in [("xcode", xcode), ("sdk", sdk)] where label == "xcode" || parts[0] == "swiftc" {
            guard let data = try? Data(contentsOf: plist),
                  let properties = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let version = properties["ProductBuildVersion"] as? String
            else { throw CargoCacheInvocation.CacheError.unsupported }
            values.append("\(label)=\(version)")
        }
        if parts[0] == "swiftc" {
            let compiler = CargoQuery(
                program: parts[1], directory: parts[2], changes: CargoQuery.changes(parts[3]), arguments: ["swiftc", "--version"]
            )
            values.append(try compiler.output(environment: environment, relocation: relocation))
        }
        return values.joined(separator: "\n")
    }
}
