import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistLogging
import TuistProcess
import TuistXCResultService
import XCResultParser

/// A run that collects per-test coverage evidence: where the test processes write, and the
/// environment that tells them to.
public struct TestCoverageEvidenceSession: Equatable, Sendable {
    public let directory: AbsolutePath
    public let environment: [String: String]

    public init(directory: AbsolutePath, environment: [String: String]) {
        self.directory = directory
        self.environment = environment
    }
}

/// The platform whose test processes a run launches, as far as collecting evidence goes.
public enum TestCoverageEvidencePlatform: Equatable, Sendable {
    case macOS
    case iOSSimulator

    /// From an xcodebuild `-destination` value; nil for devices, whose test processes cannot
    /// write to a directory on the Mac, and for the other simulators, which nothing verified.
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
/// Collected whenever the run uploads coverage (`UploadResultBundleService.uploadsCoverage`,
/// behind the `COVERAGE` client flag). Each test target's own evidence, everything its processes
/// executed, comes from the raw profiles Xcode writes per test process
/// (`TestTargetProcessCoverage`), so every target has it. Per-test and per-suite evidence needs
/// the test targets to link the TestCoverageAttribution package
/// (https://github.com/tuist/TestCoverageAttribution), which records the coverage counters each
/// test moves; Swift Testing suites also need its `.coverageAttribution` trait. `prepare` hands
/// back the environment that tells the test processes where to write; after the run `record`
/// reduces what they wrote to source files, through the functions the counters belong to and
/// `llvm-cov`'s function-to-file table, and writes the result into the result bundle. Evidence
/// only enriches a run: nothing here throws, and a run without any is a normal run.
@Mockable
public protocol TestCoverageEvidenceServicing {
    func prepare(platform: TestCoverageEvidencePlatform?, config: Tuist) async -> TestCoverageEvidenceSession?

    func record(
        session: TestCoverageEvidenceSession,
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?
    ) async -> TestCoverageEvidence?
}

public struct TestCoverageEvidenceService: TestCoverageEvidenceServicing {
    /// Where TestCoverageAttribution writes; xcodebuild passes it to the test processes with the
    /// `TEST_RUNNER_` prefix.
    static let attributionDirectoryVariable = "TEST_COVERAGE_ATTRIBUTION_DIR"

    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning
    private let xcResultService: XCResultServicing

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner(),
        xcResultService: XCResultServicing = XCResultService()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.xcResultService = xcResultService
    }

    public func prepare(platform: TestCoverageEvidencePlatform?, config: Tuist) async -> TestCoverageEvidenceSession? {
        guard UploadResultBundleService.uploadsCoverage(config: config) else { return nil }
        guard platform != nil else {
            Logger.current.debug("Coverage evidence is only collected on macOS and the iOS simulator")
            return nil
        }
        do {
            let directory = try await fileSystem.makeTemporaryDirectory(prefix: "tuist-coverage-evidence")
            return TestCoverageEvidenceSession(
                directory: directory,
                environment: ["TEST_RUNNER_\(Self.attributionDirectoryVariable)": directory.pathString]
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
        guard let resultBundlePath, (try? await fileSystem.exists(resultBundlePath)) == true else { return nil }
        let evidence = await collect(
            session: session,
            resultBundlePath: resultBundlePath,
            derivedDataDirectory: derivedDataDirectory
        )
        do {
            try evidence.write(toResultBundle: URL(fileURLWithPath: resultBundlePath.pathString))
        } catch {
            Logger.current.debug("The run's coverage evidence could not be written: \(error.localizedDescription)")
            return nil
        }
        return evidence
    }

    /// What the test processes recorded, reduced to files and lines; without scopes, its status
    /// says why there is none.
    private func collect(
        session: TestCoverageEvidenceSession,
        resultBundlePath: AbsolutePath,
        derivedDataDirectory: AbsolutePath?
    ) async -> TestCoverageEvidence {
        do {
            // TestCoverageAttribution makes a directory per test process as it loads, and removes
            // what it wrote there when recording fails.
            let processes = try FileManager.default
                .contentsOfDirectory(at: URL(fileURLWithPath: session.directory.pathString), includingPropertiesForKeys: nil)
            let outputs = processes
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("images.tsv").path) }
                .compactMap { try? CoverageObserverOutput(directory: $0) }
            guard let profile = try await profilePath(derivedDataDirectory: derivedDataDirectory) else {
                Logger.current.debug("No Coverage.profdata under the derived data; no coverage evidence")
                return TestCoverageEvidence(paths: [], scopes: [], status: processes.isEmpty ? .notLinked : .failed)
            }
            // Xcode's prefix mapping records `/^src/…` in the images and in llvm-cov's report
            // alike; both are mapped back through the image's target before the files are tied
            // to the repository, so the evidence names the same paths the coverage does.
            let prefixMaps = CompilationPrefixMaps(derivedDataDirectory: derivedDataDirectory)
            // Independent of the package's records, so it runs while they are reduced.
            async let targetsFromProcesses = processTargets(
                session: session,
                profile: profile,
                resultBundlePath: resultBundlePath,
                derivedDataDirectory: derivedDataDirectory,
                prefixMaps: prefixMaps
            )

            guard !outputs.isEmpty else {
                let targets = await targetsFromProcesses
                guard !targets.isEmpty else {
                    Logger.current.debug(processes.isEmpty
                        ? "No test process recorded coverage evidence: no test target links TestCoverageAttribution"
                        : "TestCoverageAttribution is linked, but no test process recorded coverage evidence")
                    return TestCoverageEvidence(paths: [], scopes: [], status: processes.isEmpty ? .notLinked : .failed)
                }
                var evidence = Self.reduce(outputs: [], filesByFunction: [:], targets: targets)
                evidence.status = .collected
                return evidence
            }

            var filesByFunction: [String: [String: Set<String>]] = [:]
            var mappings: [String: VerifiedCoverageMapping] = [:]
            let profileCounts = await profileCounts(profile: profile)
            for image in Set(outputs.flatMap { $0.images.values.map(\.path) }) {
                let target = CompilationPrefixMaps.targetName(ofProduct: image)
                let remap: (String) -> String = { prefixMaps.remap($0, target: target) }
                let table = await lcovTable(image: image, profile: profile, remap: remap)
                filesByFunction[image] = table.filesByFunction
                if let mapping = CoverageMapping(imagePath: image)?.remappingFiles(remap) {
                    mappings[image] = VerifiedCoverageMapping(mapping: mapping, report: table, profileCounts: profileCounts)
                }
            }
            var evidence = Self.reduce(
                outputs: outputs,
                filesByFunction: filesByFunction,
                mappings: mappings,
                targets: await targetsFromProcesses
            )
            evidence.status = evidence.scopes.isEmpty ? .failed : .collected
            return evidence
        } catch {
            Logger.current.debug("The run's coverage evidence could not be recorded: \(error.localizedDescription)")
            return TestCoverageEvidence(paths: [], scopes: [], status: .failed)
        }
    }

    // MARK: - Reduction

    /// A test's files are those of every attributable record it has (a parameterized test has
    /// one per argument); a suite's are what ran in the gaps around its tests; a target's are
    /// everything its processes executed, overlapped tests included.
    ///
    /// `targets` holds a target's files and lines read from its processes' profiles; a target in
    /// it takes those instead of the union of its records.
    static func reduce(
        outputs: [CoverageObserverOutput],
        filesByFunction: [String: [String: Set<String>]],
        mappings: [String: VerifiedCoverageMapping] = [:],
        targets: [String: [String: IndexSet]] = [:]
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
                if !record.module.isEmpty, targets[record.module] == nil {
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

        for (module, targetLines) in targets {
            add(Set(targetLines.keys), targetLines, to: Key(kind: .target, module: module, suite: "", name: ""))
        }

        let unattributed = overlapped
            .filter { files[$0] == nil }
            .map { TestCoverageEvidence.OverlappedTest(module: $0.module, suite: $0.suite, name: $0.name) }
            .sorted { ($0.module, $0.suite, $0.name) < ($1.module, $1.suite, $1.name) }
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
        return TestCoverageEvidence(paths: paths, scopes: scopes, overlappedTests: unattributed)
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
        /// Applied to each file's path as its section opens.
        var remap: (String) -> String = { $0 }

        /// Whether a line is one of the two kinds kept, told from its bytes so the rest (one line
        /// per executable line of the image) is never decoded.
        static func reads(_ line: [UInt8]) -> Bool {
            line.count > 3 && line[2] == 0x3A
                && ((line[0] == 0x53 && line[1] == 0x46) || (line[0] == 0x46 && line[1] == 0x4E)
                    || (line[0] == 0x44 && line[1] == 0x41))
        }

        mutating func read(_ line: Substring) {
            if line.hasPrefix("SF:") {
                file = remap(String(line.dropFirst(3)))
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

    private func lcovTable(image: String, profile: AbsolutePath, remap: @escaping (String) -> String) async -> LCOVFunctionTable {
        var table = LCOVFunctionTable()
        table.remap = remap
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
}

extension TestCoverageEvidenceService {
    /// Each test target's files and lines from its processes' raw profiles, which sit beside the
    /// merged profile Xcode wrote for the run; empty when there are none, as on a device.
    private func processTargets(
        session: TestCoverageEvidenceSession,
        profile: AbsolutePath,
        resultBundlePath: AbsolutePath,
        derivedDataDirectory: AbsolutePath?,
        prefixMaps: CompilationPrefixMaps
    ) async -> [String: [String: IndexSet]] {
        guard let coverageTargets = try? await CoverageExportService.coverageTargets(
            resultBundlePath: resultBundlePath,
            derivedDataDirectory: derivedDataDirectory,
            xcResultService: xcResultService
        )?.targets else { return [:] }
        let images = CoverageExportService.products(of: coverageTargets).filter { $0.kind == .image }.map(\.path)
        let bundles = coverageTargets.filter(\.isTest).compactMap { target -> TestTargetProcessCoverage.Bundle? in
            guard let image = target.buildProductPath, let module = Self.testModule(ofImage: image) else { return nil }
            return TestTargetProcessCoverage.Bundle(module: module, image: image)
        }
        // The session's directory is made right before the test action starts.
        let createdAt = (try? FileManager.default.attributesOfItem(atPath: session.directory.pathString)[.creationDate] as? Date)
            ?? .distantPast
        let result = await TestTargetProcessCoverage(fileSystem: fileSystem, commandRunner: commandRunner).collect(
            profileDirectory: profile.parentDirectory,
            createdAfter: createdAt,
            bundles: bundles,
            images: images,
            remap: { prefixMaps.remap($0, target: CompilationPrefixMaps.targetName(ofProduct: $1)) }
        )
        Logger.current.debug("""
        Target coverage from \(result.processes) process profiles: \(result.targets.count) targets, \(result
            .unmatchedProcesses) processes without a test bundle, \(result.ambiguousProcesses) with several, \(result
            .exports) llvm-cov exports
        """)
        return result.targets
    }

    /// The test module a bundle's executable belongs to: the bundle's name, as XCTest names it
    /// (`CoreTests.xctest/Contents/MacOS/CoreTests` on macOS, `CoreTests.xctest/CoreTests` elsewhere).
    static func testModule(ofImage path: String) -> String? {
        let components = path.split(separator: "/")
        guard let bundle = components.last(where: { $0.hasSuffix(".xctest") }) else { return nil }
        return String(bundle.dropLast(".xctest".count))
    }
}
