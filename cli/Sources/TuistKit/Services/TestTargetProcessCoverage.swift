import Foundation
import Path
import TuistLogging
import TuistProcess

/// Which files and lines each test target's processes executed, read from the raw profiles Xcode
/// leaves beside the run's merged profile, so a run has `target` evidence whether or not its test
/// targets link TestCoverageAttribution.
///
/// Xcode writes one `<uuid>-<pid>.profraw` per process it instruments (`%p%c`, continuous mode):
/// every test process, each parallel testing clone, and the app a UI test launches. The file holds
/// every instrumented image the process loaded, and Xcode clears the directory when the next run
/// with coverage starts. A process belongs to the test target whose bundle has a function that no
/// other image of the run has and that ran in it. Each target's profiles are merged and reported
/// by `llvm-cov` over the images whose functions ran, the way the run's own coverage is reported.
struct TestTargetProcessCoverage {
    struct Bundle: Equatable {
        /// The test module, as the result bundle and TestCoverageAttribution name it.
        let module: String
        let image: String
    }

    struct Result: Equatable {
        /// Per test module, the files its processes executed and the lines of each that ran.
        var targets: [String: [String: IndexSet]] = [:]
        /// Processes no test bundle could be told from: the app a UI test drives, a process whose
        /// test bundle ran nothing of its own.
        var unmatchedProcesses = 0
        /// Processes that ran more than one test bundle's own code; left out, since their coverage
        /// can't be split.
        var ambiguousProcesses = 0
        var processes = 0
        var exports = 0
    }

    let commandRunner: CommandRunning

    /// `images` are every instrumented image of the run, the bundles' included; `remap` maps a
    /// file as an image records it to the path the evidence names.
    func collect(
        profileDirectory: AbsolutePath,
        createdAfter date: Date,
        bundles: [Bundle],
        images: [String],
        remap: @escaping @Sendable (_ path: String, _ image: String) -> String
    ) async -> Result {
        var result = Result()
        let profiles = Self.rawProfiles(in: profileDirectory, createdAfter: date)
        result.processes = profiles.count
        guard !profiles.isEmpty, !bundles.isEmpty else { return result }
        let allImages = Array(Set(images + bundles.map(\.image))).sorted()

        let references = await concurrentMap(allImages) { image in
            (image, CoverageMapping.functionReferences(imagePath: image) ?? [])
        }
        let referencesByImage = Dictionary(uniqueKeysWithValues: references)
        var imagesHolding: [UInt64: Int] = [:]
        for (_, functions) in references {
            for function in functions {
                imagesHolding[function, default: 0] += 1
            }
        }
        let ownFunctions = bundles.map { bundle in
            (bundle.module, (referencesByImage[bundle.image] ?? []).filter { imagesHolding[$0] == 1 })
        }

        let executedByProfile = await concurrentMap(profiles) { profile in
            (profile, await executedFunctions(profile: profile.pathString))
        }
        var profilesByModule: [String: [AbsolutePath]] = [:]
        var executedByModule: [String: Set<UInt64>] = [:]
        for (profile, executed) in executedByProfile {
            let modules = ownFunctions.filter { !$0.1.isDisjoint(with: executed) }.map(\.0)
            switch modules.count {
            case 0: result.unmatchedProcesses += 1
            case 1:
                profilesByModule[modules[0], default: []].append(profile)
                executedByModule[modules[0], default: []].formUnion(executed)
            default: result.ambiguousProcesses += 1
            }
        }
        guard !profilesByModule.isEmpty else { return result }

        let directory: AbsolutePath
        do {
            directory = try AbsolutePath(validating: NSTemporaryDirectory())
                .appending(component: "tuist-target-coverage-\(UUID().uuidString)")
            try FileManager.default.createDirectory(atPath: directory.pathString, withIntermediateDirectories: true)
        } catch {
            return result
        }
        defer { try? FileManager.default.removeItem(atPath: directory.pathString) }

        let merged = await concurrentMap(profilesByModule.sorted { $0.key < $1.key }) { module, profiles in
            let output = directory.appending(component: "\(module).profdata")
            let merged = await run(["/usr/bin/xcrun", "llvm-profdata", "merge", "-sparse", "-o", output.pathString]
                + profiles.map(\.pathString)) != nil
            return (module, merged ? output : nil)
        }
        // A process loads one test bundle, so the other bundles are left out even where they link the
        // same code statically: `llvm-cov` counts a function by its name, so this bundle's copy
        // already reports it.
        let bundleImages = Set(bundles.map(\.image))
        let exports = merged.flatMap { module, profile -> [(module: String, image: String, profile: AbsolutePath)] in
            guard let profile, let executed = executedByModule[module] else { return [] }
            let own = bundles.filter { $0.module == module }.map(\.image)
            return (own + allImages.filter { !bundleImages.contains($0) })
                .filter { !(referencesByImage[$0] ?? []).isDisjoint(with: executed) }
                .map { (module, $0, profile) }
        }
        result.exports = exports.count
        let reports = await concurrentMap(exports) { export in
            (export.module, export.image, await lines(image: export.image, profile: export.profile))
        }
        for (module, image, files) in reports {
            for (file, covered) in files {
                result.targets[module, default: [:]][remap(file, image), default: IndexSet()].formUnion(covered)
            }
        }
        return result
    }

    /// This run's raw profiles: Xcode removes the previous run's when the next run with coverage
    /// starts, so anything older than the run is another run's.
    static func rawProfiles(in directory: AbsolutePath, createdAfter date: Date) -> [AbsolutePath] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.pathString)) ?? []
        return names.filter { $0.hasSuffix(".profraw") }.sorted().map { directory.appending(component: $0) }.filter {
            let attributes = try? FileManager.default.attributesOfItem(atPath: $0.pathString)
            return ((attributes?[.creationDate] as? Date) ?? .distantPast) >= date
        }
    }

    /// The functions that ran in a profile, by the reference the coverage mapping knows them by:
    /// from its sparse text form, where each function is its name followed by `# Func Hash:`.
    private func executedFunctions(profile: String) async -> Set<UInt64> {
        guard let text = await run(["/usr/bin/xcrun", "llvm-profdata", "merge", "--text", "-sparse", profile, "-o", "-"])
        else { return [] }
        return Self.functionReferences(profileText: text)
    }

    static func functionReferences(profileText text: String) -> Set<UInt64> {
        var references: Set<UInt64> = []
        var previous: Substring?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("# Func Hash:"), let previous {
                references.insert(CoverageObserverOutput.nameReference(String(previous)))
            }
            previous = line
        }
        return references
    }

    /// The files of an image whose code ran under `profile` and the lines that ran: those with a
    /// function or a line `llvm-cov` counts at least once. Dependency checkouts are left out, as
    /// the run's coverage leaves them out.
    private func lines(image: String, profile: AbsolutePath) async -> [String: IndexSet] {
        let arguments = [
            "/usr/bin/xcrun", "llvm-cov", "export", "-format=lcov", "-skip-branches",
            "-ignore-filename-regex=/(\\.build|DerivedData|SourcePackages|Pods|Carthage)/",
            "-instr-profile", profile.pathString, image,
        ]
        guard let report = await run(arguments) else { return [:] }
        return Self.executedLines(lcov: report)
    }

    static func executedLines(lcov report: String) -> [String: IndexSet] {
        var files: [String: IndexSet] = [:]
        var executed: Set<String> = []
        var file: String?
        for line in report.split(separator: "\n") {
            if line.hasPrefix("SF:") {
                file = String(line.dropFirst(3))
            } else if let file, line.hasPrefix("DA:") {
                let fields = line.dropFirst(3).split(separator: ",", maxSplits: 2)
                guard fields.count >= 2, fields[1] != "0", let number = Int(fields[0]) else { continue }
                files[file, default: IndexSet()].insert(number)
                executed.insert(file)
            } else if let file, line.hasPrefix("FNDA:"), !line.dropFirst(5).hasPrefix("0,") {
                executed.insert(file)
            }
        }
        return Dictionary(uniqueKeysWithValues: executed.map { ($0, files[$0] ?? IndexSet()) })
    }

    private func run(_ arguments: [String]) async -> String? {
        do {
            return try await commandRunner.run(arguments: arguments).concatenatedString()
        } catch {
            Logger.current.debug("\(arguments.dropFirst(2).first ?? "") failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func concurrentMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        _ transform: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        let limit = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var results: [(Int, Output)] = []
        await withTaskGroup(of: (Int, Output).self) { group in
            for (index, input) in inputs.enumerated() {
                if index >= limit, let finished = await group.next() {
                    results.append(finished)
                }
                group.addTask { (index, await transform(input)) }
            }
            for await finished in group {
                results.append(finished)
            }
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

extension CoverageMapping {
    /// The references of the functions an image's coverage mapping holds, read off the headers of
    /// its `__llvm_covfun` records without decoding them.
    static func functionReferences(imagePath path: String) -> Set<UInt64>? {
        guard let image = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              let covfun = sections(of: image, named: ["__llvm_covfun"])["__llvm_covfun"]
        else { return nil }
        var references: Set<UInt64> = []
        var offset = 0
        while offset + 28 <= covfun.count {
            references.insert(covfun.load(at: offset))
            let dataSize = Int(covfun.load(at: offset + 8) as UInt32)
            offset = (offset + 28 + dataSize + 7) & ~7
        }
        return references
    }
}
