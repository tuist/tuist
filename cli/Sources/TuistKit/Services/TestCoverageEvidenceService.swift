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
import XcodeGraph
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

extension XcodeGraph.Platform {
    /// The platform an xcodebuild `-destination` value runs tests on, a simulator's or a device's
    /// alike (`platform=iOS Simulator,…` and `generic/platform=iOS` are both iOS); nil when it
    /// names none Tuist knows.
    public init?(xcodebuildDestination destination: String) {
        let value = destination.split(separator: ",").lazy.compactMap { component -> String? in
            let pair = component.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, pair[0].lowercased().hasSuffix("platform") else { return nil }
            return pair[1].lowercased()
        }.first
        switch value?.replacingOccurrences(of: " simulator", with: "") {
        case "ios": self = .iOS
        case "macos", "os x": self = .macOS
        case "tvos": self = .tvOS
        case "watchos": self = .watchOS
        case "visionos", "xros": self = .visionOS
        default: return nil
        }
    }
}

/// Collects which files each test executed (`TestCoverageEvidence`).
///
/// Collected whenever the run uploads coverage (`UploadResultBundleService.uploadsCoverage`).
/// Each test target's own evidence, everything its processes
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

    /// `reports` are the coverage export's `llvm-cov` reports of the same run, read instead of
    /// exporting the same images again; their directory is removed once read.
    func record(
        session: TestCoverageEvidenceSession,
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?,
        reports: CoverageReports?
    ) async -> TestCoverageEvidence?
}

public struct TestCoverageEvidenceService: TestCoverageEvidenceServicing { // swiftlint:disable:this type_body_length
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
        derivedDataDirectory: AbsolutePath?,
        reports: CoverageReports?
    ) async -> TestCoverageEvidence? {
        defer {
            try? FileManager.default.removeItem(atPath: session.directory.pathString)
            if let reports { try? FileManager.default.removeItem(atPath: reports.directory.pathString) }
        }
        guard let resultBundlePath, (try? await fileSystem.exists(resultBundlePath)) == true else { return nil }
        let evidence = await collect(
            session: session,
            resultBundlePath: resultBundlePath,
            derivedDataDirectory: derivedDataDirectory,
            reports: reports
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
        derivedDataDirectory: AbsolutePath?,
        reports: CoverageReports?
    ) async -> TestCoverageEvidence {
        do {
            // TestCoverageAttribution makes a directory per test process as it loads, and removes
            // what it wrote there when recording fails.
            let processes = try FileManager.default
                .contentsOfDirectory(at: URL(fileURLWithPath: session.directory.pathString), includingPropertiesForKeys: nil)
            let launches = processes.flatMap { CoverageObserverOutput.launches(directory: $0) }
            guard let profilePath = try await profilePath(derivedDataDirectory: derivedDataDirectory) else {
                Logger.current.debug("No Coverage.profdata under the derived data; no coverage evidence")
                return TestCoverageEvidence(paths: [], scopes: [], status: processes.isEmpty ? .notLinked : .failed)
            }
            // Xcode's prefix mapping records `/^src/…` in the images and in llvm-cov's report
            // alike; both are mapped back through the image's target before the files are tied
            // to the repository, so the evidence names the same paths the coverage does.
            let prefixMaps = await CompilationPrefixMaps.ofRun(derivedDataDirectory: derivedDataDirectory)
            // Independent of the package's records, so it runs while they are reduced.
            async let fromProcesses = processCoverage(
                session: session,
                profile: profilePath,
                resultBundlePath: resultBundlePath,
                derivedDataDirectory: derivedDataDirectory,
                prefixMaps: prefixMaps,
                launches: launches
            )

            // The profile names every image's functions, so the processes' records are read only
            // once it is: their images' own names are then never inflated and hashed.
            let recorded = processes
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("images.tsv").path) }
            let profile = recorded.isEmpty ? Profile() : await profile(at: profilePath)
            let productsDirectories = Self.productsDirectories(
                derivedDataDirectory: derivedDataDirectory,
                testProductsPath: await RunMetadataStorage.current.testProductsPath
            )
            let outputs = recorded
                .compactMap { try? CoverageObserverOutput(directory: $0, namesByReference: profile.namesByReference) }
                .map { output in
                    var output = output
                    for (index, image) in output.images {
                        output.images[index]?.path = Self.buildProduct(
                            ofInstalledImage: image.path,
                            productsDirectories: productsDirectories
                        ) ?? image.path
                    }
                    return output
                }

            guard !outputs.isEmpty else {
                let processCoverage = await fromProcesses
                guard !processCoverage.targets.isEmpty || !processCoverage.launched.isEmpty else {
                    Logger.current.debug(processes.isEmpty
                        ? "No test process recorded coverage evidence: no test target links TestCoverageAttribution"
                        : "TestCoverageAttribution is linked, but no test process recorded coverage evidence")
                    return TestCoverageEvidence(paths: [], scopes: [], status: processes.isEmpty ? .notLinked : .failed)
                }
                var evidence = Self.reduce(
                    outputs: [],
                    filesByFunction: [:],
                    targets: processCoverage.targets,
                    launched: processCoverage.launched
                )
                evidence.status = .collected
                return evidence
            }

            var filesByFunction: [String: [String: Set<String>]] = [:]
            var mappings: [String: VerifiedCoverageMapping] = [:]
            let images = Set(outputs.flatMap { $0.images.values.map(\.path) })
            let architecture = CoverageExportService.architecture(ofImages: images.sorted())
            for image in images {
                let target = CompilationPrefixMaps.targetName(ofProduct: image)
                let remap: (String) -> String = { prefixMaps.remap($0, target: target) }
                let table = if let report = reports?.report(ofImage: image, profile: profilePath) {
                    lcovTable(report: report, remap: remap)
                } else {
                    await lcovTable(image: image, profile: profilePath, architecture: architecture, remap: remap)
                }
                filesByFunction[image] = table.filesByFunction
                if let mapping = CoverageMapping(imagePath: image)?.remappingFiles(remap) {
                    mappings[image] = VerifiedCoverageMapping(mapping: mapping, report: table, profileCounts: profile.counts)
                }
            }
            let processCoverage = await fromProcesses
            var evidence = Self.reduce(
                outputs: outputs,
                filesByFunction: filesByFunction,
                mappings: mappings,
                targets: processCoverage.targets,
                launched: processCoverage.launched
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
    /// it takes those instead of the union of its records. `launched` holds what the processes a
    /// scope launched executed, the app a UI test drives: it joins the test's scope (the suite's,
    /// for a launch outside a test) and its target's.
    static func reduce(
        outputs: [CoverageObserverOutput],
        filesByFunction: [String: [String: Set<String>]],
        mappings: [String: VerifiedCoverageMapping] = [:],
        targets: [String: [String: IndexSet]] = [:],
        launched: [CoverageObserverOutput.Launch.Scope: [String: IndexSet]] = [:]
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
        for (scope, scopeLines) in launched {
            let scopeFiles = Set(scopeLines.keys)
            add(scopeFiles, scopeLines, to: Key(kind: .target, module: scope.module, suite: "", name: ""))
            if scope.name.isEmpty {
                guard !scope.suite.isEmpty else { continue }
                add(scopeFiles, scopeLines, to: Key(kind: .suite, module: scope.module, suite: scope.suite, name: ""))
            } else {
                let key = Key(kind: .test, module: scope.module, suite: scope.suite, name: testName(xctestSelector: scope.name))
                add(scopeFiles, scopeLines, to: key)
            }
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
        private var pending: [UInt8] = []
        /// Applied to each file's path as its section opens.
        var remap: (String) -> String = { $0 }

        /// Reads a report as it comes, split on bytes: a chunk may end inside a multibyte
        /// character of a path. `finish` reads what follows the last newline.
        mutating func read(bytes: some Collection<UInt8>) {
            var lineStart = bytes.startIndex
            while let newline = bytes[lineStart...].firstIndex(of: 0x0A) {
                pending += bytes[lineStart ..< newline]
                if Self.reads(pending) {
                    read(Substring(String(decoding: pending, as: UTF8.self)))
                }
                pending.removeAll(keepingCapacity: true)
                lineStart = bytes.index(after: newline)
            }
            pending += bytes[lineStart...]
        }

        mutating func finish() {
            read(Substring(String(decoding: pending, as: UTF8.self)))
            pending.removeAll()
        }

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

    private func lcovTable(
        image: String,
        profile: AbsolutePath,
        architecture: String,
        remap: @escaping (String) -> String
    ) async -> LCOVFunctionTable {
        var table = LCOVFunctionTable()
        table.remap = remap
        do {
            // Dependency checkouts are left out at the source: Git cannot vouch for them, so they
            // never become evidence, and they are most of a statically linked test bundle.
            let command = [
                "/usr/bin/xcrun", "llvm-cov", "export", "-format=lcov",
                "-ignore-filename-regex=/(\\.build|DerivedData|SourcePackages|Pods|Carthage)/",
                "-instr-profile", profile.pathString, "-arch", architecture, image,
            ]
            for try await event in commandRunner.run(arguments: command, environment: Environment.current.variables) {
                guard case let .standardOutput(bytes) = event else { continue }
                table.read(bytes: bytes)
            }
            table.finish()
        } catch {
            Logger.current.debug("llvm-cov could not read \(image): \(error.localizedDescription)")
        }
        return table
    }

    /// The coverage export's report of an image: the same `llvm-cov` export, with the same
    /// filter, but `-skip-branches`, whose branch lines this table drops anyway.
    private func lcovTable(report: AbsolutePath, remap: @escaping (String) -> String) -> LCOVFunctionTable {
        var table = LCOVFunctionTable()
        table.remap = remap
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: report.pathString))
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                table.read(bytes: chunk)
            }
            table.finish()
        } catch {
            Logger.current
                .debug("The coverage export's report \(report.pathString) could not be read: \(error.localizedDescription)")
        }
        return table
    }

    /// The merged profile's functions: their counter values, what the decoded coverage mapping is
    /// checked with against `llvm-cov`'s report of the same profile, and their names by the
    /// reference the images' `__llvm_prf_data` knows them by.
    struct Profile: Equatable {
        var counts: [CoverageMapping.FunctionKey: [UInt64]] = [:]
        var namesByReference: [UInt64: String] = [:]
    }

    private func profile(at path: AbsolutePath) async -> Profile {
        do {
            let text = try await commandRunner
                .run(arguments: ["/usr/bin/xcrun", "llvm-profdata", "merge", "--text", path.pathString, "-o", "-"])
                .concatenatedString()
            return Self.profile(text: text)
        } catch {
            Logger.current.debug("llvm-profdata could not read \(path.pathString): \(error.localizedDescription)")
            return Profile()
        }
    }

    /// A text profile lists each function as its name, `# Func Hash:` and the hash, `# Num
    /// Counters:` and how many, `# Counter Values:` and one value per line.
    static func profile(text: String) -> Profile {
        var result = Profile()
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
            let name = String(lines[index])
            let reference = CoverageObserverOutput.nameReference(name)
            result.counts[CoverageMapping.FunctionKey(reference: reference, hash: hash)] =
                lines[(index + 6) ..< (index + 6 + count)].map { UInt64($0) ?? 0 }
            result.namesByReference[reference] = name
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
    /// merged profile Xcode wrote for the run, and those of the processes the tests launched;
    /// empty when there are none, as on a device.
    private func processCoverage(
        session: TestCoverageEvidenceSession,
        profile: AbsolutePath,
        resultBundlePath: AbsolutePath,
        derivedDataDirectory: AbsolutePath?,
        prefixMaps: CompilationPrefixMaps,
        launches: [CoverageObserverOutput.Launch]
    ) async -> TestTargetProcessCoverage.Result {
        guard let coverageTargets = try? await CoverageExportService.coverageTargets(
            resultBundlePath: resultBundlePath,
            derivedDataDirectory: derivedDataDirectory,
            xcResultService: xcResultService
        )?.targets else { return TestTargetProcessCoverage.Result() }
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
            launches: launches,
            remap: { prefixMaps.remap($0, target: CompilationPrefixMaps.targetName(ofProduct: $1)) }
        )
        Logger.current.debug("""
        Target coverage from \(result.processes) process profiles: \(result.targets.count) targets, \(result
            .launchedProcesses) processes launched by \(result.launched.count) scopes, \(result
            .unmatchedProcesses) processes without a test bundle or a recorded launch, \(result
            .ambiguousProcesses) with several test bundles, \(result.exports) llvm-cov exports
        """)
        return result
    }

    /// The build product an image was installed from, for an image in a simulator clone or one that
    /// no longer exists: a parallel test run installs the bundles into clones (`XCTestDevices`) that
    /// Xcode deletes after it, in the background, so a clone's image can vanish between a check and
    /// the read. The product is found by the image's path from its outermost bundle on.
    static func buildProduct(ofInstalledImage path: String, productsDirectories: [String]) -> String? {
        guard path.contains("/XCTestDevices/") || !FileManager.default.fileExists(atPath: path) else { return nil }
        let components = path.split(separator: "/")
        guard let bundle = components.firstIndex(where: { $0.hasSuffix(".app") || $0.hasSuffix(".xctest") })
        else { return nil }
        let relativePath = components[bundle...].joined(separator: "/")
        return productsDirectories
            .map { ($0 as NSString).appendingPathComponent(relativePath) }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Each configuration's products directory: the derived data's, and, for a run without
    /// building, the `.xctestproducts` bundle's, since the derived data then holds no products.
    static func productsDirectories(derivedDataDirectory: AbsolutePath?, testProductsPath: AbsolutePath?) -> [String] {
        CoverageExportService.productRoots(derivedDataDirectory: derivedDataDirectory, testProductsPath: testProductsPath)
            .flatMap { root in
                let names = (try? FileManager.default.contentsOfDirectory(atPath: root.pathString)) ?? []
                return names.sorted().map { root.appending(component: $0).pathString }
            }
    }

    /// The test module a bundle's executable belongs to: the bundle's name, as XCTest names it
    /// (`CoreTests.xctest/Contents/MacOS/CoreTests` on macOS, `CoreTests.xctest/CoreTests` elsewhere).
    static func testModule(ofImage path: String) -> String? {
        let components = path.split(separator: "/")
        guard let bundle = components.last(where: { $0.hasSuffix(".xctest") }) else { return nil }
        return String(bundle.dropLast(".xctest".count))
    }
}
