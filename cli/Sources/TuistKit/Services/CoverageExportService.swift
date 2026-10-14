import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistConfig
import TuistEnvironment
import TuistLogging
import TuistProcess
import TuistXCResultService
import XCResultParser

/// Measures a run's line coverage with `llvm-cov` over the test products, instead of reading the
/// report `xccov` wrote into the result bundle.
///
/// `xccov` only reports the source files of targets the test action built, so code that came
/// from the binary cache, or that was compiled with a coverage prefix map, is missing from it.
/// `llvm-cov export` reads the coverage mapping of every instrumented image with the run's merged
/// profile, which covers both. What the bundle's report still provides is the list of products
/// the action built (the images to export) and which target compiled each file; the lines, their
/// counts and the functions come from `llvm-cov`.
///
/// The export runs right after the test action, while the derived data still holds this run's
/// profile (a stress pass over the same derived data replaces it), and goes into the result bundle
/// as ``CoverageExport/fileName`` with the compiler's own paths: the upload ties it to the
/// repository with the coverage manifest, the way it ties `xccov`'s output. Coverage only
/// enriches a run, so nothing here throws, and a run that cannot be exported falls back to the
/// bundle's report.
@Mockable
public protocol CoverageExportServicing {
    /// The export's path inside the bundle, or nil when the run uploads no coverage, has none, or
    /// could not be exported.
    func export(
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async -> AbsolutePath?
}

public struct CoverageExportService: CoverageExportServicing {
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

    public func export(
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async -> AbsolutePath? {
        guard UploadResultBundleService.uploadsCoverage(config: config), let resultBundlePath,
              (try? await fileSystem.exists(resultBundlePath)) == true
        else { return nil }
        do {
            guard let targets = try await xcResultService.coverageTargets(path: resultBundlePath) else { return nil }
            guard let profile = try await profilePath(derivedDataDirectory: derivedDataDirectory) else {
                Logger.current.debug("No Coverage.profdata under the derived data; the bundle's coverage report is used")
                return nil
            }
            let products = Self.products(of: targets)
            guard !products.isEmpty else {
                Logger.current.debug("No instrumented product among the test products; the bundle's coverage report is used")
                return nil
            }
            let output = resultBundlePath.appending(component: CoverageExport.fileName)
            try await fileSystem.runInTemporaryDirectory(prefix: "tuist-coverage-export") { directory in
                async let reports = export(products: products, profile: profile, into: directory)
                let spans = await Self.spans(of: products)
                let exported = try await reports
                try await CoverageExport.write(
                    reports: products.map { exported[$0.path]! },
                    attribution: CoverageExport.Attribution(targets: targets),
                    spans: spans,
                    demangle: demangle,
                    to: output
                )
            }
            return output
        } catch {
            AlertController.current.warning(
                .alert(
                    "Failed to export the code coverage of \(resultBundlePath.pathString) with llvm-cov: \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    /// The function spans of every product's coverage mapping, decoded one product at a time
    /// alongside the exports.
    static func spans(of products: [Product]) async -> FunctionSpans {
        await withTaskGroup(of: FunctionSpans.self) { group in
            for product in products {
                group.addTask {
                    var spans = FunctionSpans()
                    switch product.kind {
                    case .image: spans.add(CoverageMapping(imagePath: product.path))
                    case .archive: for mapping in CoverageMapping.mappings(archivePath: product.path) {
                            spans.add(mapping)
                        }
                    }
                    return spans
                }
            }
            var spans = FunctionSpans()
            for await decoded in group {
                spans.merge(decoded)
            }
            return spans
        }
    }

    /// A product `llvm-cov` reads: a Mach-O image (an app, a test bundle, a dynamic framework,
    /// an object file), or the archive of a static target. The archive is read too, the way
    /// xccov reads it: the code of a static target that no image linked still counts, with
    /// nothing covered, since the target was built for the run.
    struct Product: Equatable {
        enum Kind {
            case image
            case archive
        }

        let path: String
        let kind: Kind
    }

    /// The targets' products that carry coverage mappings, each once.
    static func products(of targets: [XcodeCoverageTarget]) -> [Product] {
        var products: [Product] = []
        var seen: Set<String> = []
        for path in targets.compactMap(\.buildProductPath) {
            let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: path))
                .map {
                    ($0 as NSString).isAbsolutePath ? $0 : ((path as NSString).deletingLastPathComponent as NSString)
                        .appendingPathComponent($0)
                }
                ?? path
            guard seen.insert(resolved).inserted, let kind = Self.kind(of: resolved) else { continue }
            products.append(Product(path: resolved, kind: kind))
        }
        return products
    }

    /// From the file's magic number: Mach-O (thin or universal) or `ar` archive.
    static func kind(of path: String) -> Product.Kind? {
        guard let handle = FileHandle(forReadingAtPath: path), let data = try? handle.read(upToCount: 8), data.count == 8 else {
            return nil
        }
        try? handle.close()
        if data.elementsEqual("!<arch>\n".utf8) { return .archive }
        let magic = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA].contains(magic) ? .image : nil
    }

    // MARK: - llvm-cov

    /// Exports every product to its own LCOV file, as many at a time as there are cores. A
    /// failing export fails the whole run's export: a missing product would leave its code out
    /// of the figures.
    private func export(
        products: [Product],
        profile: AbsolutePath,
        into directory: AbsolutePath
    ) async throws -> [String: AbsolutePath] {
        var reports: [String: AbsolutePath] = [:]
        let limit = max(1, ProcessInfo.processInfo.activeProcessorCount)
        try await withThrowingTaskGroup(of: (String, AbsolutePath).self) { group in
            for (index, product) in products.enumerated() {
                if index >= limit, let (finished, report) = try await group.next() {
                    reports[finished] = report
                }
                let report = directory.appending(component: "\(index).lcov")
                group.addTask {
                    try await export(product: product, profile: profile, to: report)
                    return (product.path, report)
                }
            }
            for try await (path, report) in group {
                reports[path] = report
            }
        }
        return reports
    }

    /// One product's LCOV report. `llvm-cov` reads an archive, and a universal image, only for
    /// a named architecture: the one the tests ran as, which is the host's.
    private func export(product: Product, profile: AbsolutePath, to report: AbsolutePath) async throws {
        let architecture = ["-arch", Self.hostArchitecture]
        do {
            if product.kind == .image {
                do {
                    return try await run(llvmCov: [], image: product.path, profile: profile, to: report)
                } catch is CommandError {}
            }
            try await run(llvmCov: architecture, image: product.path, profile: profile, to: report)
        } catch let error as CommandError {
            // A product built without instrumentation, or whose mapping holds no function, has
            // nothing to report; xccov lists it with no files either.
            guard case let .terminated(_, stderr, _) = error, stderr.contains("no coverage data found") else { throw error }
            guard FileManager.default.createFile(atPath: report.pathString, contents: nil) else {
                throw CoverageExportError.cannotWrite(report)
            }
        }
    }

    private func run(llvmCov options: [String], image: String, profile: AbsolutePath, to report: AbsolutePath) async throws {
        guard FileManager.default.createFile(atPath: report.pathString, contents: nil) else {
            throw CoverageExportError.cannotWrite(report)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: report.pathString))
        defer { try? handle.close() }
        // Dependency checkouts are left out at the source: Git cannot vouch for them, so they never
        // reach the server, and they are most of a statically linked test bundle.
        let arguments = [
            "/usr/bin/xcrun", "llvm-cov", "export", "-format=lcov", "-skip-branches",
            "-ignore-filename-regex=/(\\.build|DerivedData|SourcePackages|Pods|Carthage)/",
            "-instr-profile", profile.pathString,
        ] + options + [image]
        for try await event in commandRunner.run(arguments: arguments, environment: Environment.current.variables) {
            guard case let .standardOutput(bytes) = event else { continue }
            try handle.write(contentsOf: Data(bytes))
        }
    }

    static var hostArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    /// Swift symbols read the way xccov names functions (`Type.method(label:)`), from one
    /// `swift-demangle` over the names of a whole image. The tool takes its input on standard
    /// input, which is why it is not run through the command runner. Nothing else changes.
    private func demangle(_ names: [String]) async throws -> [String: String] {
        let mangled = names.filter(Self.isSwiftMangled)
        guard !mangled.isEmpty else { return [:] }
        return try await fileSystem.runInTemporaryDirectory(prefix: "tuist-coverage-demangle") { directory in
            let input = directory.appending(component: "names.txt")
            let output = directory.appending(component: "demangled.txt")
            try Data((mangled.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: input.pathString))
            guard FileManager.default.createFile(atPath: output.pathString, contents: nil) else {
                throw CoverageExportError.cannotWrite(output)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["swift-demangle", "-compact", "-simplified"]
            process.environment = Environment.current.variables
            process.standardInput = try FileHandle(forReadingFrom: URL(fileURLWithPath: input.pathString))
            process.standardOutput = try FileHandle(forWritingTo: URL(fileURLWithPath: output.pathString))
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [:] }
            let demangled = try String(contentsOf: URL(fileURLWithPath: output.pathString), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            guard demangled.count >= mangled.count else { return [:] }
            return Dictionary(
                zip(mangled, demangled.prefix(mangled.count).map(String.init)),
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    static func isSwiftMangled(_ name: String) -> Bool {
        name.hasPrefix("$s") || name.hasPrefix("_$s") || name.hasPrefix("$S") || name.hasPrefix("_$S") || name.hasPrefix("_T0")
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

enum CoverageExportError: LocalizedError {
    case cannotWrite(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .cannotWrite(path): "Could not write the coverage export to \(path.pathString)"
        }
    }
}

/// The lines each function spans in each file, from the images' coverage mappings: what tells
/// a function's executable and covered lines apart from the file's, the way xccov counts them
/// (from the function's first line to its last, nested closures included).
struct FunctionSpans: Sendable {
    struct Key: Hashable {
        let file: String
        let reference: UInt64
    }

    private(set) var spans: [Key: ClosedRange<Int>] = [:]

    mutating func add(_ mapping: CoverageMapping?) {
        guard let mapping else { return }
        for function in mapping.functions {
            var byFile: [Int: ClosedRange<Int>] = [:]
            for entry in function.regions where entry.region.kind == .code {
                let range = entry.region.lineStart ... max(entry.region.lineStart, entry.region.lineEnd)
                byFile[entry.file] = byFile[entry.file].map { min($0.lowerBound, range.lowerBound) ... max(
                    $0.upperBound,
                    range.upperBound
                ) } ?? range
            }
            for (file, range) in byFile {
                let key = Key(file: mapping.files[file], reference: function.reference)
                if spans[key] == nil { spans[key] = range }
            }
        }
    }

    /// A function with local linkage (a closure, a private function) is known to the profile and
    /// the mapping by its name prefixed with its source file, the way the compiler recorded it.
    mutating func merge(_ other: FunctionSpans) {
        spans.merge(other.spans) { first, _ in first }
    }

    func span(file: String, function: String) -> ClosedRange<Int>? {
        spans[Key(file: file, reference: CoverageObserverOutput.nameReference(function))]
            ?? spans[Key(file: file, reference: CoverageObserverOutput.nameReference("\(file):\(function)"))]
    }
}

/// The run's coverage as `llvm-cov` exported it, written into the result bundle as one
/// ``XcodeCoverageFile`` per line with the compiler's paths and no Git blob, for the upload to
/// tie to the repository.
public enum CoverageExport {
    public static let fileName = "tuist_coverage_export.ndjson"

    /// Which targets compiled each file, from the bundle's coverage report.
    struct Attribution {
        private var targetsByPath: [String: [String]] = [:]
        private var testTargets: Set<String> = []

        init(targets: [XcodeCoverageTarget]) {
            for target in targets {
                if target.isTest { testTargets.insert(target.name) }
                for path in target.files where !(targetsByPath[path] ?? []).contains(target.name) {
                    targetsByPath[path, default: []].append(target.name)
                }
            }
        }

        /// The non-test targets that compiled the file, or the test bundles when only those did,
        /// in which case the file is test code.
        func targets(of path: String) -> (targets: [String], isTest: Bool) {
            let targets = targetsByPath[path] ?? []
            let productTargets = targets.filter { !testTargets.contains($0) }
            return (productTargets.isEmpty ? targets : productTargets, !targets.isEmpty && productTargets.isEmpty)
        }
    }

    /// A file's section of an LCOV report: `SF:<file>` opens it, `FN:<line>,<name>` lists a
    /// function, `FNDA:<count>,<name>` how often it ran, `DA:<line>,<count>` an executable line
    /// and its count, and `end_of_record` closes it. The rest is dropped as it goes by.
    struct LCOVRecord {
        var path: String
        var lines: [(line: Int, count: UInt64)] = []
        var functions: [(line: Int, name: String)] = []
        var counts: [String: UInt64] = [:]
    }

    /// Reads an LCOV report one section at a time.
    static func forEachRecord(in report: AbsolutePath, _ body: (LCOVRecord) throws -> Void) throws {
        var record: LCOVRecord?
        try forEachLine(of: report) { line in
            if line.hasPrefix("SF:") {
                record = LCOVRecord(path: String(line.dropFirst(3)))
            } else if line.hasPrefix("DA:") {
                let fields = line.dropFirst(3).split(separator: ",", maxSplits: 2)
                guard fields.count >= 2, let number = Int(fields[0]), let count = UInt64(fields[1]) else { return }
                record?.lines.append((number, count))
            } else if line.hasPrefix("FN:"), let comma = line.firstIndex(of: ",") {
                guard let number = Int(line[line.index(line.startIndex, offsetBy: 3) ..< comma]) else { return }
                record?.functions.append((number, String(line[line.index(after: comma)...])))
            } else if line.hasPrefix("FNDA:"), let comma = line.firstIndex(of: ",") {
                guard let count = UInt64(line[line.index(line.startIndex, offsetBy: 5) ..< comma]) else { return }
                record?.counts[String(line[line.index(after: comma)...])] = count
            } else if line == "end_of_record", let finished = record {
                record = nil
                try body(finished)
            }
        }
    }

    /// The function names an LCOV report lists.
    static func functionNames(in report: AbsolutePath) throws -> [String] {
        var names: Set<String> = []
        try forEachLine(of: report) { line in
            guard line.hasPrefix("FN:"), let comma = line.firstIndex(of: ",") else { return }
            names.insert(String(line[line.index(after: comma)...]))
        }
        return names.sorted()
    }

    /// Instrumented code bumps its counters without atomics unless the build asked for them, so
    /// tests running in parallel can lose increments, and a count derived by subtracting one
    /// counter from another wraps around. Such a count reads as zero.
    static func count(_ value: UInt64) -> Int {
        value >= 1 << 47 ? 0 : Int(value)
    }

    /// One file per section the reports hold, the first report that lists it winning (every
    /// image reports the same lines for a file): its lines and counts, and its functions with
    /// their executable and covered lines within the span the mapping gives them, or until the
    /// next function starts when the mapping has none.
    static func write(
        reports: [AbsolutePath],
        attribution: Attribution,
        spans: FunctionSpans,
        demangle: ([String]) async throws -> [String: String],
        to output: AbsolutePath
    ) async throws {
        guard FileManager.default.createFile(atPath: output.pathString, contents: nil) else {
            throw CoverageExportError.cannotWrite(output)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output.pathString))
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        var emitted: Set<String> = []
        for report in reports {
            let demangled = try await demangle(functionNames(in: report))
            try forEachRecord(in: report) { record in
                guard emitted.insert(record.path).inserted else { return }
                let file = Self.file(record, attribution: attribution, spans: spans, demangled: demangled)
                try autoreleasepool {
                    try handle.write(contentsOf: try encoder.encode(file))
                    try handle.write(contentsOf: Data([UInt8(ascii: "\n")]))
                }
            }
        }
    }

    static func file(
        _ record: LCOVRecord,
        attribution: Attribution,
        spans: FunctionSpans,
        demangled: [String: String]
    ) -> XcodeCoverageFile {
        let lines = record.lines.sorted { $0.line < $1.line }
        let counts = lines.map { count($0.count) }
        let (targets, isTest) = attribution.targets(of: record.path)
        let starts = record.functions.map(\.line).sorted()
        let functions = record.functions.sorted { ($0.line, $0.name) < ($1.line, $1.name) }.map { function in
            let span = spans.span(file: record.path, function: function.name)
                ?? function.line ... (starts.first { $0 > function.line }.map { $0 - 1 } ?? Int.max)
            var executable = 0
            var covered = 0
            for (index, line) in lines.enumerated() where span.contains(line.line) {
                executable += 1
                if counts[index] > 0 { covered += 1 }
            }
            return XcodeCoverageFunction(
                name: demangled[function.name] ?? function.name,
                lineNumber: function.line,
                executionCount: count(record.counts[function.name] ?? 0),
                coveredLines: covered,
                executableLines: executable
            )
        }
        // Test code is left out of every figure, so only its counts travel.
        return XcodeCoverageFile(
            path: record.path,
            gitBlobId: nil,
            targets: targets,
            isTest: isTest,
            coveredLines: counts.filter { $0 > 0 }.count,
            executableLines: lines.count,
            lineNumbers: isTest ? [] : lines.map(\.line),
            executionCounts: isTest ? [] : counts,
            functions: isTest ? [] : functions
        )
    }

    // MARK: - Tying the export to the repository

    /// The compiler's paths of every file the export holds.
    public static func paths(of export: AbsolutePath) throws -> [String] {
        var paths: [String] = []
        try forEachLine(of: export) { line in
            guard !line.isEmpty else { return }
            paths.append(try JSONDecoder().decode(ExportedPath.self, from: Data(line.utf8)).path)
        }
        return paths
    }

    private struct ExportedPath: Decodable {
        let path: String
    }

    /// Writes the export's files to `output` relative to the checkout and with their Git blobs,
    /// leaving out what is not the repository's own code, as the `xccov` parser does.
    public static func tie(
        export: AbsolutePath,
        manifest: XcodeCoverageManifest,
        into output: AbsolutePath
    ) throws -> XcodeCoverageSummary {
        let roots = XcodeCoverageParser.roots(manifest.rootDirectories)
        let blobIdsByPath = Dictionary(manifest.files.map { ($0.path, $0.gitBlobId) }, uniquingKeysWith: { first, _ in first })
        let repositoryPaths = Set(manifest.files.map(\.path))
        guard FileManager.default.createFile(atPath: output.pathString, contents: nil) else {
            throw CoverageExportError.cannotWrite(output)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output.pathString))
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var fileCount = 0
        try forEachLine(of: export) { line in
            guard !line.isEmpty else { return }
            try autoreleasepool {
                let exported = try decoder.decode(XcodeCoverageFile.self, from: Data(line.utf8))
                let path = XcodeCoverageParser.relativize(exported.path, to: roots)
                guard !path.hasPrefix("/"), !XcodeCoverageParser.isDependencyPath(path),
                      repositoryPaths.isEmpty || repositoryPaths.contains(path)
                else { return }
                let file = XcodeCoverageFile(
                    path: path,
                    gitBlobId: blobIdsByPath[path],
                    targets: exported.targets,
                    isTest: exported.isTest,
                    coveredLines: exported.coveredLines,
                    executableLines: exported.executableLines,
                    lineNumbers: exported.lineNumbers,
                    executionCounts: exported.executionCounts,
                    functions: exported.functions
                )
                try handle.write(contentsOf: try encoder.encode(file))
                try handle.write(contentsOf: Data([UInt8(ascii: "\n")]))
                fileCount += 1
            }
        }
        return XcodeCoverageSummary(partial: manifest.partial, fileCount: fileCount)
    }

    /// Reads a file one line at a time, split on bytes so a chunk boundary inside a multibyte
    /// character of a path is harmless, without holding more than one chunk and one line.
    static func forEachLine(of path: AbsolutePath, _ body: (Substring) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path.pathString))
        defer { try? handle.close() }
        var pending: [UInt8] = []
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            var lineStart = chunk.startIndex
            while let newline = chunk[lineStart...].firstIndex(of: 0x0A) {
                pending += chunk[lineStart ..< newline]
                try body(Substring(String(decoding: pending, as: UTF8.self)))
                pending.removeAll(keepingCapacity: true)
                lineStart = chunk.index(after: newline)
            }
            pending += chunk[lineStart...]
        }
        if !pending.isEmpty { try body(Substring(String(decoding: pending, as: UTF8.self))) }
    }
}
