import FileSystem
import Foundation
import Path
import TuistLogging
import TuistProcess
import TuistSupport

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
///
/// A process no test bundle claims, such as the app a UI test drives, belongs to the scope that
/// TestCoverageAttribution recorded launching it, by the pid in the profile's name; each scope's
/// profiles are reported the same way, over the images other than the test bundles.
struct TestTargetProcessCoverage {
    struct Bundle: Equatable {
        /// The test module, as the result bundle and TestCoverageAttribution name it.
        let module: String
        let image: String
    }

    struct Result: Equatable {
        /// Per test module, the files its processes executed and the lines of each that ran.
        var targets: [String: [String: IndexSet]] = [:]
        /// Per scope that launched a process, the files those processes executed and their lines.
        var launched: [CoverageObserverOutput.Launch.Scope: [String: IndexSet]] = [:]
        /// Processes no test bundle could be told from and no recorded launch claims: the app of a UI
        /// test target that doesn't link TestCoverageAttribution, a process whose test bundle ran
        /// nothing of its own.
        var unmatchedProcesses = 0
        var launchedProcesses = 0
        /// Processes that ran more than one test bundle's own code; left out, since their coverage
        /// can't be split.
        var ambiguousProcesses = 0
        var processes = 0
        var exports = 0
    }

    let fileSystem: FileSysteming
    let commandRunner: CommandRunning

    /// `images` are every instrumented image of the run, the bundles' included; `remap` maps a
    /// file as an image records it to the path the evidence names.
    func collect(
        profileDirectory: AbsolutePath,
        createdAfter date: Date,
        bundles: [Bundle],
        images: [String],
        launches: [CoverageObserverOutput.Launch] = [],
        remap: @escaping @Sendable (_ path: String, _ image: String) -> String
    ) async -> Result {
        var result = Result()
        let profiles = Self.rawProfiles(in: profileDirectory, createdAfter: date)
        result.processes = profiles.count
        // A scheme that gathers coverage only for the app leaves its UI test bundles out of the
        // run's targets, but the app's launches are still there to attribute.
        guard !profiles.isEmpty, !bundles.isEmpty || !launches.isEmpty else { return result }
        let allImages = Array(Set(images + bundles.map(\.image))).sorted()
        let architecture = CoverageExportService.architecture(ofImages: allImages)

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
        let scopeByProcess = Dictionary(launches.map { ($0.processIdentifier, $0.scope) }, uniquingKeysWith: { $1 })
        var profilesByOwner: [Owner: [AbsolutePath]] = [:]
        var executedByOwner: [Owner: Set<UInt64>] = [:]
        for (profile, executed) in executedByProfile {
            let modules = ownFunctions.filter { !$0.1.isDisjoint(with: executed) }.map(\.0)
            let owner: Owner
            switch modules.count {
            case 0:
                guard let scope = Self.processIdentifier(ofProfile: profile).flatMap({ scopeByProcess[$0] }) else {
                    result.unmatchedProcesses += 1
                    continue
                }
                result.launchedProcesses += 1
                owner = .launch(scope)
            case 1: owner = .target(modules[0])
            default:
                result.ambiguousProcesses += 1
                continue
            }
            profilesByOwner[owner, default: []].append(profile)
            executedByOwner[owner, default: []].formUnion(executed)
        }
        guard !profilesByOwner.isEmpty else { return result }

        let reports = try? await fileSystem.runInTemporaryDirectory(prefix: "tuist-target-coverage") { directory in
            let merged = await concurrentMap(Array(profilesByOwner.enumerated())) { index, entry in
                let output = directory.appending(component: "\(index).profdata")
                let merged = await run(["/usr/bin/xcrun", "llvm-profdata", "merge", "-sparse", "-o", output.pathString]
                    + entry.value.map(\.pathString)) != nil
                return (entry.key, merged ? output : nil)
            }
            // A process loads one test bundle, so the other bundles are left out even where they link
            // the same code statically: `llvm-cov` counts a function by its name, so this bundle's
            // copy already reports it. A launched process loads none.
            let bundleImages = Set(bundles.map(\.image))
            let exports = merged.flatMap { owner, profile -> [(owner: Owner, image: String, profile: AbsolutePath)] in
                guard let profile, let executed = executedByOwner[owner] else { return [] }
                let own: [String]
                switch owner {
                case let .target(module): own = bundles.filter { $0.module == module }.map(\.image)
                case .launch: own = []
                }
                return (own + allImages.filter { !bundleImages.contains($0) })
                    .filter { !(referencesByImage[$0] ?? []).isDisjoint(with: executed) }
                    .map { (owner, $0, profile) }
            }
            return await concurrentMap(exports) { export in
                (
                    export.owner,
                    export.image,
                    await lines(image: export.image, profile: export.profile, architecture: architecture)
                )
            }
        }
        result.exports = reports?.count ?? 0
        for (owner, image, files) in reports ?? [] {
            for (file, covered) in files {
                switch owner {
                case let .target(module):
                    result.targets[module, default: [:]][remap(file, image), default: IndexSet()].formUnion(covered)
                case let .launch(scope):
                    result.launched[scope, default: [:]][remap(file, image), default: IndexSet()].formUnion(covered)
                }
            }
        }
        return result
    }

    private enum Owner: Hashable {
        case target(String)
        case launch(CoverageObserverOutput.Launch.Scope)
    }

    /// The pid in a raw profile's name, `<uuid>-<pid>.profraw` as Xcode names it (`%p`).
    static func processIdentifier(ofProfile profile: AbsolutePath) -> Int32? {
        guard profile.extension == "profraw" else { return nil }
        return profile.basenameWithoutExt.split(separator: "-").last.flatMap { Int32($0) }
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
    /// the run's coverage leaves them out. A universal image, such as a framework from the binary
    /// cache, is read for the run's `architecture`.
    private func lines(image: String, profile: AbsolutePath, architecture: String) async -> [String: IndexSet] {
        guard let report = await run(Self.exportArguments(image: image, profile: profile, architecture: architecture))
        else { return [:] }
        return Self.executedLines(lcov: report)
    }

    /// `llvm-cov` reads a universal image only for a named architecture; `-arch` names the slice a
    /// thin image already is, so it is passed for every image.
    static func exportArguments(image: String, profile: AbsolutePath, architecture: String) -> [String] {
        [
            "/usr/bin/xcrun", "llvm-cov", "export", "-format=lcov", "-skip-branches",
            "-ignore-filename-regex=/(\\.build|DerivedData|SourcePackages|Pods|Carthage)/",
            "-instr-profile", profile.pathString, "-arch", architecture, image,
        ]
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

    /// As many at a time as there are cores, in the order given.
    private func concurrentMap<Input, Output>(
        _ inputs: [Input],
        _ transform: @escaping (Input) async -> Output
    ) async -> [Output] {
        (try? await inputs.concurrentMap(maxConcurrentTasks: max(1, ProcessInfo.processInfo.activeProcessorCount), transform))
            ?? []
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
