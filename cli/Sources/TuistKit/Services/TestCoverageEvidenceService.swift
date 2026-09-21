import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistServer
import XCResultParser

/// A run that collects per-test coverage evidence: where the observer writes, and the
/// environment that injects it into the test hosts.
public struct TestCoverageEvidenceSession: Equatable, Sendable {
    public let directory: AbsolutePath
    public let environment: [String: String]

    public init(directory: AbsolutePath, environment: [String: String]) {
        self.directory = directory
        self.environment = environment
    }
}

/// The platform whose test hosts a run launches, as far as injecting the observer goes.
public enum TestCoverageEvidencePlatform: Equatable, Sendable {
    case macOS
    case iOSSimulator

    /// From an xcodebuild `-destination` value; nil for the platforms the observer is not built
    /// for (devices, and the other simulators), where a wrong library would keep the host from
    /// launching.
    public init?(destination: String) {
        let value = destination.lowercased()
        if value.contains("platform=macos") || value.contains("platform=os x") {
            self = .macOS
        } else if value.contains("platform=ios simulator") {
            self = .iOSSimulator
        } else {
            return nil
        }
    }
}

/// Collects which files each test executed (`TestCoverageEvidence`).
///
/// Opt-in with `TUIST_COVERAGE_EVIDENCE=1`, behind the `COVERAGE` client flag. `prepare` hands back the environment that injects
/// the
/// coverage observer into the test hosts; after the run `record` reduces what the observer wrote
/// (the coverage counters each test moved) to source files, through the functions the counters
/// belong to and `llvm-cov`'s function-to-file table, and writes the result into the result
/// bundle. XCTest needs nothing from the project; Swift Testing needs the `.coverageAttribution`
/// trait (`cli/CoverageObserver/CoverageAttributionTrait.swift`). Evidence only enriches a run:
/// nothing here throws, and a run without the observer is a normal run.
@Mockable
public protocol TestCoverageEvidenceServicing {
    func prepare(platform: TestCoverageEvidencePlatform?) async -> TestCoverageEvidenceSession?

    func record(
        session: TestCoverageEvidenceSession,
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?
    ) async -> TestCoverageEvidence?
}

public struct TestCoverageEvidenceService: TestCoverageEvidenceServicing {
    static let enabledVariable = "TUIST_COVERAGE_EVIDENCE"
    static let observerPathVariable = "TUIST_COVERAGE_OBSERVER_PATH"
    static let observerDirectoryVariable = "TUIST_COVERAGE_OBSERVER_DIR"

    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(fileSystem: FileSysteming = FileSystem(), commandRunner: CommandRunning = CommandRunner()) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func prepare(platform: TestCoverageEvidencePlatform?) async -> TestCoverageEvidenceSession? {
        guard ClientFeatureFlags.contains("COVERAGE"), Environment.current.isVariableTruthy(Self.enabledVariable)
        else { return nil }
        guard let platform else {
            Logger.current.debug("Coverage evidence is only collected on macOS and the iOS simulator")
            return nil
        }
        do {
            guard let observer = try await observerPath(platform: platform) else {
                Logger.current.debug("The coverage observer was not found next to tuist; no coverage evidence")
                return nil
            }
            let directory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-coverage-evidence")
            var libraries = [observer.pathString]
            if platform == .iOSSimulator {
                // On the simulator the variable replaces Xcode's own injection unless it carries it
                // too, and a host without it never connects to xcodebuild.
                guard let injector = try await xctestBundleInjector() else { return nil }
                libraries.append(injector.pathString)
            }
            return TestCoverageEvidenceSession(
                directory: directory,
                environment: [
                    "TEST_RUNNER_DYLD_INSERT_LIBRARIES": libraries.joined(separator: ":"),
                    "TEST_RUNNER_\(Self.observerDirectoryVariable)": directory.pathString,
                ]
            )
        } catch {
            Logger.current.debug("Coverage evidence could not be set up: \(error.localizedDescription)")
            return nil
        }
    }

    public func record(
        session: TestCoverageEvidenceSession,
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?
    ) async -> TestCoverageEvidence? {
        defer { try? FileManager.default.removeItem(atPath: session.directory.pathString) }
        do {
            guard let resultBundlePath, try await fileSystem.exists(resultBundlePath) else { return nil }
            let outputs = try FileManager.default
                .contentsOfDirectory(at: URL(fileURLWithPath: session.directory.pathString), includingPropertiesForKeys: nil)
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("images.tsv").path) }
                .compactMap { try? CoverageObserverOutput(directory: $0) }
            guard !outputs.isEmpty else { return nil }
            guard let profile = try await profilePath(derivedDataDirectory: derivedDataDirectory) else {
                Logger.current.debug("No Coverage.profdata under the derived data; no coverage evidence")
                return nil
            }

            var filesByFunction: [String: [String: Set<String>]] = [:]
            var mappings: [String: VerifiedCoverageMapping] = [:]
            let profileCounts = await profileCounts(profile: profile)
            for image in Set(outputs.flatMap { $0.images.values.map(\.path) }) {
                let table = await lcovTable(image: image, profile: profile)
                filesByFunction[image] = table.filesByFunction
                if let mapping = CoverageMapping(imagePath: image) {
                    mappings[image] = VerifiedCoverageMapping(mapping: mapping, report: table, profileCounts: profileCounts)
                }
            }
            let evidence = Self.reduce(outputs: outputs, filesByFunction: filesByFunction, mappings: mappings)
            guard !evidence.scopes.isEmpty else { return nil }
            try evidence.write(toResultBundle: URL(fileURLWithPath: resultBundlePath.pathString))
            return evidence
        } catch {
            Logger.current.debug("The run's coverage evidence could not be recorded: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Reduction

    /// A test's files are those of every attributable record it has (a parameterized test has
    /// one per argument); a suite's are what ran in the gaps around its tests; a target's are
    /// everything its processes executed, overlapped tests included.
    static func reduce(
        outputs: [CoverageObserverOutput],
        filesByFunction: [String: [String: Set<String>]],
        mappings: [String: VerifiedCoverageMapping] = [:]
    ) -> TestCoverageEvidence {
        struct Key: Hashable {
            let kind: TestCoverageEvidence.Kind
            let module: String
            let suite: String
            let name: String
        }
        var files: [Key: Set<String>] = [:]
        var lines: [Key: [String: IndexSet]] = [:]
        var overlapped: Set<Key> = []

        func add(_ recordFiles: Set<String>, _ recordLines: [String: IndexSet], to key: Key) {
            files[key, default: []].formUnion(recordFiles)
            for (path, covered) in recordLines {
                lines[key, default: [:]][path, default: IndexSet()].formUnion(covered)
            }
        }

        for output in outputs {
            for record in output.records {
                let recordLines = output.lines(of: record, mappings: mappings)
                var recordFiles: Set<String> = []
                for (image, functions) in output.functions(of: record) {
                    guard let table = filesByFunction[image] else { continue }
                    for function in functions {
                        recordFiles.formUnion(table[function] ?? [])
                    }
                }
                if !record.module.isEmpty {
                    add(recordFiles, recordLines, to: Key(kind: .target, module: record.module, suite: "", name: ""))
                }
                switch record.kind {
                case .gap:
                    guard !record.suite.isEmpty else { continue }
                    add(recordFiles, recordLines, to: Key(kind: .suite, module: record.module, suite: record.suite, name: ""))
                case .xctest, .swiftTesting:
                    let name = record.kind == .xctest ? testName(xctestSelector: record.name) : record.name
                    let key = Key(kind: .test, module: record.module, suite: record.suite, name: name)
                    if record.overlapped {
                        overlapped.insert(key)
                    } else {
                        add(recordFiles, recordLines, to: key)
                    }
                }
            }
        }

        let unattributed = overlapped.filter { files[$0] == nil }.count
        let paths = Set(files.values.flatMap { $0 }).sorted()
        let indexByPath = Dictionary(uniqueKeysWithValues: paths.enumerated().map { ($1, $0) })
        let scopes = files
            .filter { !$0.value.isEmpty }
            .map { key, value in
                let scopeFiles = value.sorted()
                let scopeLines = lines[key] ?? [:]
                return TestCoverageEvidence.Scope(
                    kind: key.kind, module: key.module, suite: key.suite, name: key.name,
                    files: scopeFiles.compactMap { indexByPath[$0] },
                    lines: scopeLines.isEmpty ? nil : scopeFiles.map {
                        TestCoverageEvidence.Scope.ranges(of: scopeLines[$0] ?? IndexSet())
                    }
                )
            }
            .sorted { ($0.module, $0.suite, $0.name, $0.kind.rawValue) < ($1.module, $1.suite, $1.name, $1.kind.rawValue) }
        return TestCoverageEvidence(paths: paths, scopes: scopes, unattributedTests: unattributed)
    }

    /// The name the result bundle gives an XCTest test, from its selector: `testAdd` and the
    /// bridged forms of a throwing or asynchronous Swift test (`testAddAndReturnError:`,
    /// `testAddWithCompletionHandler:`) are all `testAdd()`.
    static func testName(xctestSelector selector: String) -> String {
        var name = selector
        for suffix in ["AndReturnError:", "WithCompletionHandler:"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.hasSuffix("()") ? name : name + "()"
    }

    /// Reads LCOV a line at a time: `SF:<file>` opens a file's section, `FN:<line>,<function>`
    /// lists a function of it, under the name the profile data refers to it by, and
    /// `DA:<line>,<count>` an executable line. The rest is dropped as it goes by.
    struct LCOVFunctionTable {
        private(set) var filesByFunction: [String: Set<String>] = [:]
        /// Per file, the executable lines and those that ran, as `llvm-cov` reports them.
        private(set) var executableLines: [String: IndexSet] = [:]
        private(set) var coveredLines: [String: IndexSet] = [:]
        private var file: String?

        /// Whether a line is one of the two kinds kept, told from its bytes so the rest (one line
        /// per executable line of the image) is never decoded.
        static func reads(_ line: [UInt8]) -> Bool {
            line.count > 3 && line[2] == 0x3A
                && ((line[0] == 0x53 && line[1] == 0x46) || (line[0] == 0x46 && line[1] == 0x4E)
                    || (line[0] == 0x44 && line[1] == 0x41))
        }

        mutating func read(_ line: Substring) {
            if line.hasPrefix("SF:") {
                file = String(line.dropFirst(3))
            } else if line.hasPrefix("FN:"), let file, let comma = line.firstIndex(of: ",") {
                filesByFunction[String(line[line.index(after: comma)...]), default: []].insert(file)
            } else if line.hasPrefix("DA:"), let file {
                let fields = line.dropFirst(3).split(separator: ",", maxSplits: 2)
                guard fields.count >= 2, let number = Int(fields[0]) else { return }
                executableLines[file, default: IndexSet()].insert(number)
                if fields[1] != "0" { coveredLines[file, default: IndexSet()].insert(number) }
            }
        }
    }

    // MARK: - Tools and files

    private func lcovTable(image: String, profile: AbsolutePath) async -> LCOVFunctionTable {
        var table = LCOVFunctionTable()
        do {
            // Split on bytes: a chunk may end inside a multibyte character of a path. Dependency
            // checkouts are left out at the source: Git cannot vouch for them, so they never
            // become evidence, and they are most of a statically linked test bundle.
            var pending: [UInt8] = []
            let command = [
                "/usr/bin/xcrun", "llvm-cov", "export", "-format=lcov",
                "-ignore-filename-regex=/(\\.build|DerivedData|SourcePackages|Pods|Carthage)/",
                "-instr-profile", profile.pathString, image,
            ]
            for try await event in commandRunner.run(arguments: command, environment: Environment.current.variables) {
                guard case let .standardOutput(bytes) = event else { continue }
                var lineStart = bytes.startIndex
                while let newline = bytes[lineStart...].firstIndex(of: 0x0A) {
                    pending += bytes[lineStart ..< newline]
                    if LCOVFunctionTable.reads(pending) {
                        table.read(Substring(String(decoding: pending, as: UTF8.self)))
                    }
                    pending.removeAll(keepingCapacity: true)
                    lineStart = bytes.index(after: newline)
                }
                pending += bytes[lineStart...]
            }
            table.read(Substring(String(decoding: pending, as: UTF8.self)))
        } catch {
            Logger.current.debug("llvm-cov could not read \(image): \(error.localizedDescription)")
        }
        return table
    }

    /// The run's counter values per function, from the merged profile as text: what the decoded
    /// coverage mapping is checked with against `llvm-cov`'s report of the same profile.
    private func profileCounts(profile: AbsolutePath) async -> [CoverageMapping.FunctionKey: [UInt64]] {
        do {
            let text = try await commandRunner
                .run(arguments: ["/usr/bin/xcrun", "llvm-profdata", "merge", "--text", profile.pathString, "-o", "-"])
                .concatenatedString()
            return Self.profileCounts(text: text)
        } catch {
            Logger.current.debug("llvm-profdata could not read \(profile.pathString): \(error.localizedDescription)")
            return [:]
        }
    }

    /// A text profile lists each function as its name, `# Func Hash:` and the hash, `# Num
    /// Counters:` and how many, `# Counter Values:` and one value per line.
    static func profileCounts(text: String) -> [CoverageMapping.FunctionKey: [UInt64]] {
        var result: [CoverageMapping.FunctionKey: [UInt64]] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index + 5 < lines.count {
            guard lines[index + 1].hasPrefix("# Func Hash:"), let hash = UInt64(lines[index + 2]),
                  lines[index + 3].hasPrefix("# Num Counters:"), let count = Int(lines[index + 4]),
                  index + 5 + count < lines.count
            else {
                index += 1
                continue
            }
            let key = CoverageMapping.FunctionKey(
                reference: CoverageObserverOutput.nameReference(String(lines[index])), hash: hash
            )
            result[key] = lines[(index + 6) ..< (index + 6 + count)].map { UInt64($0) ?? 0 }
            index += 6 + count
        }
        return result
    }

    /// Xcode merges a run's profiles into `Build/ProfileData/<device>/Coverage.profdata`; the
    /// newest one is this run's.
    private func profilePath(derivedDataDirectory: AbsolutePath?) async throws -> AbsolutePath? {
        guard let derivedDataDirectory else { return nil }
        let profileData = derivedDataDirectory.appending(components: "Build", "ProfileData")
        guard try await fileSystem.exists(profileData) else { return nil }
        let profiles = try await fileSystem.glob(directory: profileData, include: ["*/Coverage.profdata"]).collect()
        return profiles.max { modificationDate($0) < modificationDate($1) }
    }

    private func modificationDate(_ path: AbsolutePath) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path.pathString)[.modificationDate] as? Date) ?? .distantPast
    }

    private func observerPath(platform: TestCoverageEvidencePlatform) async throws -> AbsolutePath? {
        let name = switch platform {
        case .macOS: "libtuist_coverage_observer.dylib"
        case .iOSSimulator: "libtuist_coverage_observer_iossimulator.dylib"
        }
        var directories: [AbsolutePath] = []
        if let override = Environment.current.variables[Self.observerPathVariable], !override.isEmpty {
            directories.append(try AbsolutePath(validating: override))
        } else if let bundle = try? AbsolutePath(validating: Bundle(for: ManifestLoader.self).bundleURL.path) {
            directories += [bundle, bundle.parentDirectory, bundle.parentDirectory.appending(component: "lib")]
        }
        for directory in directories {
            let candidate = directory.appending(component: name)
            if try await fileSystem.exists(candidate) { return candidate }
        }
        return nil
    }

    private func xctestBundleInjector() async throws -> AbsolutePath? {
        let platformPath = try await commandRunner
            .run(arguments: ["/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-platform-path"])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let injector = try AbsolutePath(validating: platformPath)
            .appending(components: "Developer", "usr", "lib", "libXCTestBundleInject.dylib")
        return try await fileSystem.exists(injector) ? injector : nil
    }
}
