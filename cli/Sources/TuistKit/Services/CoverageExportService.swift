import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistConfig
import TuistCore
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
    /// could not be exported. `runStartedAt` is when the test action started: a profile older
    /// than that is an earlier run's.
    func export(
        resultBundlePath: AbsolutePath?,
        derivedDataDirectory: AbsolutePath?,
        config: Tuist,
        runStartedAt: Date
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
        config: Tuist,
        runStartedAt: Date
    ) async -> AbsolutePath? {
        // Without a project to upload to, the run sends nothing, so nothing is measured.
        guard config.fullHandle != nil, UploadResultBundleService.uploadsCoverage(config: config), let resultBundlePath,
              (try? await fileSystem.exists(resultBundlePath)) == true
        else { return nil }
        do {
            guard let targets = try await coverageTargets(
                resultBundlePath: resultBundlePath,
                derivedDataDirectory: derivedDataDirectory
            )
            else { return nil }
            guard let profile = try await profilePath(derivedDataDirectory: derivedDataDirectory, newerThan: runStartedAt)
            else {
                Logger.current
                    .debug("No Coverage.profdata of this run under the derived data; the bundle's coverage report is used")
                return nil
            }
            let products = Self.products(of: targets)
            guard !products.isEmpty else {
                Logger.current.debug("No instrumented product among the test products; the bundle's coverage report is used")
                return nil
            }
            let output = resultBundlePath.appending(component: CoverageExport.fileName)
            let prefixMaps = CompilationPrefixMaps(derivedDataDirectory: derivedDataDirectory)
            let targetNames = products.map { CompilationPrefixMaps.targetName(ofProduct: $0.path) }
            try await fileSystem.runInTemporaryDirectory(prefix: "tuist-coverage-export") { directory in
                async let reports = export(
                    products: products,
                    profile: profile,
                    architecture: products.first { $0.kind == .image }.flatMap { Self.architecture(ofImage: $0.path) }
                        ?? Self.hostArchitecture,
                    into: directory
                )
                let spans = await Self.spans(of: products)
                let exported = try await reports
                try await CoverageExport.write(
                    reports: products.map { exported[$0.path]! },
                    attribution: CoverageExport.Attribution(targets: targets.map { target in
                        XcodeCoverageTarget(
                            name: target.name,
                            buildProductPath: target.buildProductPath,
                            files: target.files.map { prefixMaps.remap(
                                $0,
                                target: CompilationPrefixMaps.targetName(ofProduct: target.name)
                            ) }
                        )
                    }),
                    spans: spans,
                    demangle: demangle,
                    remap: { path, report in prefixMaps.remap(path, target: targetNames[report]) },
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

    /// The run's targets, from the build's graph when the build recorded them (`tuist test`,
    /// including the targets the binary cache replaced, which the bundle's report never lists),
    /// else from the bundle's report.
    private func coverageTargets(
        resultBundlePath: AbsolutePath,
        derivedDataDirectory: AbsolutePath?
    ) async throws -> [XcodeCoverageTarget]? {
        if let sources = await RunMetadataStorage.current.coverageBuildSources, !sources.targets.isEmpty {
            var roots: [AbsolutePath] = []
            if let derivedDataDirectory { roots.append(derivedDataDirectory.appending(components: "Build", "Products")) }
            if let testProductsPath = await RunMetadataStorage.current.testProductsPath { roots.append(testProductsPath) }
            return Self.targets(sources, productRoots: roots)
        }
        return try await xcResultService.coverageTargets(path: resultBundlePath)
    }

    /// The build's targets with the products the run used: for a target built from source, its
    /// product in the products directory the run's test bundles are in (the one under `roots`
    /// that holds most of them, the newest on a tie); for a target the binary cache replaced, the
    /// xcframework slice of that directory's platform.
    static func targets(_ sources: CoverageBuildSources, productRoots roots: [AbsolutePath]) -> [XcodeCoverageTarget] {
        let candidates = roots.flatMap { root -> [AbsolutePath] in
            let children = (try? FileManager.default.contentsOfDirectory(atPath: root.pathString)) ?? []
            return [root] + children.map { root.appending(component: $0) }
        }
        let names = sources.targets.map(\.name)
        var counted: [(directory: AbsolutePath, products: Int)] = []
        for directory in candidates {
            let products = names.filter { FileManager.default.fileExists(atPath: directory.appending(component: $0).pathString) }
                .count
            if products > 0 { counted.append((directory, products)) }
        }
        let productsDirectory: AbsolutePath? = counted.max { lhs, rhs in
            if lhs.products != rhs.products { return lhs.products < rhs.products }
            return modificationDate(lhs.directory) < modificationDate(rhs.directory)
        }?.directory
        let platform: (name: String, simulator: Bool)? = productsDirectory.map { Self.platform(ofProductsDirectory: $0.basename) }

        return sources.targets.map { target in
            var product: String?
            if let productsDirectory {
                let path = productsDirectory.appending(component: target.name)
                if FileManager.default.fileExists(atPath: path.pathString) { product = executable(inProduct: path) }
            }
            if product == nil, let platform {
                product = target.binaries
                    .first {
                        $0.platform == platform.name && $0.simulator == platform.simulator && FileManager.default
                            .fileExists(atPath: $0.path)
                    }?
                    .path
            }
            let files = target.files.flatMap { file -> [String] in
                file.hasPrefix("/") ? [file] : sources.rootDirectories.map { "\($0)/\(file)" }
            }
            return XcodeCoverageTarget(name: target.name, buildProductPath: product, files: files)
        }
    }

    /// The platform a products directory is for, from its name: `Debug` is macOS,
    /// `Debug-iphonesimulator` the iOS simulator, `Release-appletvos` tvOS devices.
    static func platform(ofProductsDirectory name: String) -> (name: String, simulator: Bool) {
        guard let dash = name.lastIndex(of: "-") else { return ("macos", false) }
        let suffix = String(name[name.index(after: dash)...])
        let simulator = suffix.hasSuffix("simulator")
        let base = simulator ? String(suffix.dropLast("simulator".count)) : suffix
            .hasSuffix("os") ? String(suffix.dropLast(2)) : suffix
        switch base {
        case "iphone": return ("ios", simulator)
        case "appletv": return ("tvos", simulator)
        case "watch": return ("watchos", simulator)
        case "xr": return ("xros", simulator)
        case "macosx", "mac": return ("macos", false)
        default: return (base, simulator)
        }
    }

    /// The binary inside a product: the file itself, or a bundle's executable by its
    /// `CFBundleExecutable` (`Contents/MacOS/<name>` on macOS, `Versions/Current/<name>` in a
    /// framework, `<name>` elsewhere).
    static func executable(inProduct path: AbsolutePath) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else { return path.pathString }
        let plists = ["Contents/Info.plist", "Info.plist", "Versions/Current/Resources/Info.plist", "Resources/Info.plist"]
        let executable = plists.lazy
            .compactMap {
                try? Data(contentsOf: URL(fileURLWithPath: path.appending(try! RelativePath(validating: $0)).pathString))
            }
            .compactMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            .compactMap { $0["CFBundleExecutable"] as? String }
            .first ?? path.basenameWithoutExt
        for location in ["Contents/MacOS/\(executable)", "Versions/Current/\(executable)", executable] {
            let candidate = path.appending(try! RelativePath(validating: location))
            if FileManager.default.fileExists(atPath: candidate.pathString) { return candidate.pathString }
        }
        return nil
    }

    private static func modificationDate(_ path: AbsolutePath) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path.pathString)[.modificationDate] as? Date) ?? .distantPast
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
        architecture: String,
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
                    try await export(product: product, profile: profile, architecture: architecture, to: report)
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
    /// a named architecture: the one the run's images were built for, which the host's is not
    /// under Rosetta.
    private func export(product: Product, profile: AbsolutePath, architecture: String, to report: AbsolutePath) async throws {
        let architecture = ["-arch", architecture]
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

    /// The architecture of a thin Mach-O image, from its header; nil for a universal one or
    /// anything else.
    static func architecture(ofImage path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path), let data = try? handle.read(upToCount: 8), data.count == 8 else {
            return nil
        }
        try? handle.close()
        guard data.prefix(4).withUnsafeBytes({ $0.loadUnaligned(as: UInt32.self) }) == 0xFEED_FACF else { return nil }
        switch data.dropFirst(4).withUnsafeBytes({ $0.loadUnaligned(as: UInt32.self) }) {
        case 0x0100_000C: return "arm64"
        case 0x0100_0007: return "x86_64"
        default: return nil
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
    /// newest one is this run's, as long as it was written after the run started: an older one is
    /// an earlier run's, left in the derived data by a run without coverage.
    private func profilePath(derivedDataDirectory: AbsolutePath?, newerThan date: Date) async throws -> AbsolutePath? {
        guard let derivedDataDirectory else { return nil }
        let profileData = derivedDataDirectory.appending(components: "Build", "ProfileData")
        guard try await fileSystem.exists(profileData) else { return nil }
        let profiles = try await fileSystem.glob(directory: profileData, include: ["*/Coverage.profdata"]).collect()
        return Self.newest(profiles, writtenAfter: date)
    }

    static func newest(_ profiles: [AbsolutePath], writtenAfter date: Date) -> AbsolutePath? {
        guard let newest = profiles.max(by: { modificationDate($0) < modificationDate($1) }) else { return nil }
        return modificationDate(newest) < date ? nil : newest
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
        remap: (_ path: String, _ report: Int) -> String = { path, _ in path },
        to output: AbsolutePath
    ) async throws {
        guard FileManager.default.createFile(atPath: output.pathString, contents: nil) else {
            throw CoverageExportError.cannotWrite(output)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output.pathString))
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        var emitted: Set<String> = []
        for (index, report) in reports.enumerated() {
            let demangled = try await demangle(functionNames(in: report))
            try forEachRecord(in: report) { record in
                // Xcode's prefix mapping records `/^src/…`; the file is emitted under the path it
                // maps back to, while the mapping's spans know it by the recorded one.
                let path = remap(record.path, index)
                guard emitted.insert(path).inserted else { return }
                let file = Self.file(record, path: path, attribution: attribution, spans: spans, demangled: demangled)
                try autoreleasepool {
                    try handle.write(contentsOf: try encoder.encode(file))
                    try handle.write(contentsOf: Data([UInt8(ascii: "\n")]))
                }
            }
        }
    }

    static func file(
        _ record: LCOVRecord,
        path: String? = nil,
        attribution: Attribution,
        spans: FunctionSpans,
        demangled: [String: String]
    ) -> XcodeCoverageFile {
        let path = path ?? record.path
        let lines = record.lines.sorted { $0.line < $1.line }
        let counts = lines.map { count($0.count) }
        let (targets, isTest) = attribution.targets(of: path)
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
            path: path,
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
        let decoder = JSONDecoder()
        try forEachLine(of: export) { line in
            guard !line.isEmpty else { return }
            paths.append(try decoder.decode(ExportedPath.self, from: Data(line.utf8)).path)
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

/// The reverse of Xcode's prefix mapping, per target: `compilation-prefix-map.json` in each
/// target's intermediates (`Build/Intermediates.noindex/<project>.build/<configuration>/
/// <target>.build/`) maps the aliases the compiler recorded (`/^src`, `/^root`, `/^built`, …)
/// back to the directories of this build. A coverage build maps only when the project opted in
/// (`enableCoveragePrefixMapping`), since `xccov` drops mapped files.
struct CompilationPrefixMaps {
    /// Each target's entries, longest alias first, so the most specific one wins.
    private(set) var mapsByTarget: [String: [(alias: String, path: String)]] = [:]

    init(mapsByTarget: [String: [String: String]]) {
        self.mapsByTarget = mapsByTarget.mapValues { map in
            map.map { (alias: $0.key, path: $0.value) }.sorted { $0.alias.count > $1.alias.count }
        }
    }

    init(derivedDataDirectory: AbsolutePath?) {
        guard let derivedDataDirectory else {
            self.init(mapsByTarget: [:])
            return
        }
        let intermediates = derivedDataDirectory.appending(components: "Build", "Intermediates.noindex")
        var maps: [String: [String: String]] = [:]
        for project in (try? FileManager.default.contentsOfDirectory(atPath: intermediates.pathString)) ?? []
            where project.hasSuffix(".build")
        {
            let projectDirectory = intermediates.appending(component: project)
            for configuration in (try? FileManager.default.contentsOfDirectory(atPath: projectDirectory.pathString)) ?? [] {
                let configurationDirectory = projectDirectory.appending(component: configuration)
                for target in (try? FileManager.default.contentsOfDirectory(atPath: configurationDirectory.pathString)) ?? []
                    where target.hasSuffix(".build")
                {
                    let file = configurationDirectory.appending(components: target, "compilation-prefix-map.json")
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.pathString)),
                          let map = try? JSONDecoder().decode([String: String].self, from: data)
                    else { continue }
                    maps[String(target.dropLast(".build".count)), default: [:]].merge(map) { first, _ in first }
                }
            }
        }
        self.init(mapsByTarget: maps)
    }

    /// The name of the target a product was built from: the product's file name without its
    /// extension (`Lib` for `Lib.framework/Versions/A/Lib`, `libLib.a`, `App.app/App`).
    static func targetName(ofProduct path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        let bundle = components.last { component in
            ["app", "appex", "framework", "xctest", "bundle", "a", "o", "dylib"].contains((component as NSString).pathExtension)
        } ?? components.last ?? path
        var name = (bundle as NSString).deletingPathExtension
        if (bundle as NSString).pathExtension == "a", name.hasPrefix("lib") { name = String(name.dropFirst(3)) }
        return name
    }

    /// `path` with its alias replaced: through the target's own map when it knows the alias,
    /// else through the first map whose result exists on disk, else the first that knows it. A
    /// path without an alias, or one no map knows, is returned as is.
    func remap(_ path: String, target: String) -> String {
        guard path.hasPrefix("/^") else { return path }
        if let own = mapsByTarget[target], let remapped = Self.remap(path, through: own) { return remapped }
        let candidates = mapsByTarget.sorted { $0.key < $1.key }.compactMap { Self.remap(path, through: $0.value) }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates.first ?? path
    }

    private static func remap(_ path: String, through entries: [(alias: String, path: String)]) -> String? {
        for entry in entries where path == entry.alias || path.hasPrefix(entry.alias + "/") {
            return entry.path + path.dropFirst(entry.alias.count)
        }
        return nil
    }
}
