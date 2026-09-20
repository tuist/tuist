import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
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
/// Opt-in with `TUIST_COVERAGE_EVIDENCE=1`. `prepare` hands back the environment that injects the
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
        guard Environment.current.isVariableTruthy(Self.enabledVariable) else { return nil }
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
            for image in Set(outputs.flatMap { $0.images.values.map(\.path) }) {
                filesByFunction[image] = await self.filesByFunction(image: image, profile: profile)
            }
            let evidence = Self.reduce(outputs: outputs, filesByFunction: filesByFunction)
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
        filesByFunction: [String: [String: Set<String>]]
    ) -> TestCoverageEvidence {
        struct Key: Hashable {
            let kind: TestCoverageEvidence.Kind
            let module: String
            let suite: String
            let name: String
        }
        var files: [Key: Set<String>] = [:]
        var overlapped: Set<Key> = []

        for output in outputs {
            for record in output.records {
                var recordFiles: Set<String> = []
                for (image, functions) in output.functions(of: record) {
                    guard let table = filesByFunction[image] else { continue }
                    for function in functions { recordFiles.formUnion(table[function] ?? []) }
                }
                if !record.module.isEmpty {
                    files[Key(kind: .target, module: record.module, suite: "", name: ""), default: []].formUnion(recordFiles)
                }
                switch record.kind {
                case .gap:
                    guard !record.suite.isEmpty else { continue }
                    files[Key(kind: .suite, module: record.module, suite: record.suite, name: ""), default: []]
                        .formUnion(recordFiles)
                case .xctest, .swiftTesting:
                    let name = record.kind == .xctest ? testName(xctestSelector: record.name) : record.name
                    let key = Key(kind: .test, module: record.module, suite: record.suite, name: name)
                    if record.overlapped {
                        overlapped.insert(key)
                    } else {
                        files[key, default: []].formUnion(recordFiles)
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
                TestCoverageEvidence.Scope(
                    kind: key.kind, module: key.module, suite: key.suite, name: key.name,
                    files: value.compactMap { indexByPath[$0] }.sorted()
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

    /// Reads LCOV a line at a time: `SF:<file>` opens a file's section and `FN:<line>,<function>`
    /// lists a function of it, under the name the profile data refers to it by. The per-line
    /// records, the bulk of the output, are dropped as they go by.
    struct LCOVFunctionTable {
        private(set) var filesByFunction: [String: Set<String>] = [:]
        private var file: String?

        /// Whether a line is one of the two kinds kept, told from its bytes so the rest (one line
        /// per executable line of the image) is never decoded.
        static func reads(_ line: [UInt8]) -> Bool {
            line.count > 3 && line[2] == 0x3A
                && ((line[0] == 0x53 && line[1] == 0x46) || (line[0] == 0x46 && line[1] == 0x4E))
        }

        mutating func read(_ line: Substring) {
            if line.hasPrefix("SF:") {
                file = String(line.dropFirst(3))
            } else if line.hasPrefix("FN:"), let file, let comma = line.firstIndex(of: ",") {
                filesByFunction[String(line[line.index(after: comma)...]), default: []].insert(file)
            }
        }
    }

    // MARK: - Tools and files

    private func filesByFunction(image: String, profile: AbsolutePath) async -> [String: Set<String>] {
        do {
            var table = LCOVFunctionTable()
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
            return table.filesByFunction
        } catch {
            Logger.current.debug("llvm-cov could not read \(image): \(error.localizedDescription)")
            return [:]
        }
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
