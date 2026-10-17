import FileSystem
import Foundation
import Mockable
import Path
import TuistEnvironment
import TuistLogging
import TuistServer
import XcodeGraph
import XCResultParser

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Works out whether a run executed its tests in parallel or serially, per target, and records
/// the answer in the result bundle (`TestExecutionModes.fileName`) so the run's report carries it
/// whoever processes the bundle.
///
/// `-parallel-testing-enabled YES|NO` on the command line decides for every target. Otherwise
/// each target's own setting decides: `ParallelizationEnabled` in the xctestrun when the run had
/// one (`build-for-testing`, `test-without-building`), the `parallelizable` attribute of the
/// scheme's testable references or of the test plan it runs, and for `tuist test` the generated
/// scheme itself. A target with no explicit setting runs its Swift Testing tests in parallel, so
/// it counts as parallel. Without any of those the mode stays unknown: nothing is guessed.
/// Behind the `COVERAGE` client flag with the rest of coverage and test selection.
@Mockable
public protocol TestExecutionModeResolving {
    /// Resolves the modes and writes them into the bundle. `schemeTargets` are the modes the
    /// caller already knows per target (see `targets(scheme:testPlan:)`); the xctestrun and the
    /// scheme file named in the arguments refine them. Nil when nothing could be resolved; never
    /// throws, since the modes only enrich the run.
    func record(
        resultBundlePath: AbsolutePath?,
        xcodebuildArguments: [String],
        derivedDataPath: AbsolutePath?,
        schemeTargets: [String: String]
    ) async -> TestExecutionModes?
}

public struct TestExecutionModeResolver: TestExecutionModeResolving {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func record(
        resultBundlePath: AbsolutePath?,
        xcodebuildArguments: [String],
        derivedDataPath: AbsolutePath?,
        schemeTargets: [String: String]
    ) async -> TestExecutionModes? {
        guard ClientFeatureFlags.contains("COVERAGE") else { return nil }
        do {
            var targets = schemeTargets
            targets.merge(try await schemeFileTargets(xcodebuildArguments: xcodebuildArguments)) { _, new in new }
            targets.merge(
                try await xctestrunTargets(xcodebuildArguments: xcodebuildArguments, derivedDataPath: derivedDataPath)
            ) { _, new in new }

            guard let modes = Self.resolve(xcodebuildArguments: xcodebuildArguments, targets: targets) else { return nil }
            if let resultBundlePath, try await fileSystem.exists(resultBundlePath) {
                try modes.write(toResultBundle: URL(fileURLWithPath: resultBundlePath.pathString))
            }
            return modes
        } catch {
            Logger.current.debug("The run's execution mode could not be recorded: \(error.localizedDescription)")
            return nil
        }
    }

    /// The modes from the command line and the targets' settings.
    static func resolve(xcodebuildArguments: [String], targets: [String: String]) -> TestExecutionModes? {
        if let forced = forcedMode(xcodebuildArguments: xcodebuildArguments) {
            return TestExecutionModes(run: forced, targets: targets.mapValues { _ in forced })
        }
        guard !targets.isEmpty else { return nil }
        let run = targets.values.contains(TestExecutionModes.parallel) ? TestExecutionModes.parallel : TestExecutionModes.serial
        return TestExecutionModes(run: run, targets: targets)
    }

    static func forcedMode(xcodebuildArguments: [String]) -> String? {
        guard let value = value(of: "-parallel-testing-enabled", in: xcodebuildArguments) else { return nil }
        switch value.uppercased() {
        case "YES", "TRUE", "1": return TestExecutionModes.parallel
        case "NO", "FALSE", "0": return TestExecutionModes.serial
        default: return nil
        }
    }

    /// The modes of a generated scheme's test targets: the test plan's when one runs (the named
    /// one, else the default), the test action's otherwise.
    public static func targets(scheme: Scheme, testPlan: String?) -> [String: String] {
        guard let testAction = scheme.testAction else { return [:] }
        let plans = testAction.testPlans ?? []
        let plan = testPlan.flatMap { name in plans.first { $0.name == name } } ?? plans.first { $0.isDefault }
        let testables = plan?.testTargets ?? testAction.targets
        return Dictionary(
            testables.filter { !$0.isSkipped }.map { ($0.target.name, mode(for: $0.parallelization)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func mode(for parallelization: TestableTarget.Parallelization) -> String {
        switch parallelization {
        case .none: TestExecutionModes.serial
        case .all, .swiftTestingOnly: TestExecutionModes.parallel
        }
    }

    /// `ParallelizationEnabled` per test target in an xctestrun, in both the format Xcode writes
    /// for a scheme (`TestConfigurations[].TestTargets[]`, version 2) and the flat one (version 1,
    /// one dictionary per target keyed by its name).
    static func parallelizationByTarget(xctestrun data: Data) throws -> [String: Bool] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        var result: [String: Bool] = [:]
        if let configurations = plist["TestConfigurations"] as? [[String: Any]] {
            for configuration in configurations {
                for target in configuration["TestTargets"] as? [[String: Any]] ?? [] {
                    guard let name = (target["BlueprintName"] ?? target["ProductModuleName"]) as? String else { continue }
                    result[name] = target["ParallelizationEnabled"] as? Bool ?? false
                }
            }
        } else {
            for (key, value) in plist where key != "__xctestrun_metadata__" {
                guard let target = value as? [String: Any] else { continue }
                let name = (target["BlueprintName"] ?? target["ProductModuleName"]) as? String ?? key
                result[name] = target["ParallelizationEnabled"] as? Bool ?? false
            }
        }
        return result
    }

    /// What a scheme file says: the testable references with their `parallelizable` attribute
    /// (`YES`, `NO`, or absent for Xcode's default of parallel Swift Testing), and the test plans
    /// it references, as `container:`-relative paths.
    static func parseScheme(_ data: Data) -> (targets: [String: String], testPlans: [String]) {
        let parser = SchemeParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return (parser.targets, parser.testPlans)
    }

    /// The parallelization of a test plan's targets: a target is parallel only when the plan says
    /// so.
    static func parseTestPlan(_ data: Data) throws -> [String: String] {
        guard let plan = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = plan["testTargets"] as? [[String: Any]]
        else { return [:] }
        var result: [String: String] = [:]
        for target in targets {
            guard let name = (target["target"] as? [String: Any])?["name"] as? String else { continue }
            let parallel = target["parallelizable"] as? Bool ?? false
            result[name] = parallel ? TestExecutionModes.parallel : TestExecutionModes.serial
        }
        return result
    }

    private final class SchemeParser: NSObject, XMLParserDelegate {
        var targets: [String: String] = [:]
        var testPlans: [String] = []
        private var inTestAction = false
        private var inTestableReference = false
        private var currentParallelizable: String?

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "TestAction":
                inTestAction = true
            case "TestableReference" where inTestAction:
                inTestableReference = true
                currentParallelizable = attributes["parallelizable"]
            case "BuildableReference" where inTestableReference:
                if let name = attributes["BlueprintName"] {
                    targets[name] = currentParallelizable == "NO" ? TestExecutionModes.serial : TestExecutionModes.parallel
                }
            case "TestPlanReference" where inTestAction:
                if let reference = attributes["reference"] { testPlans.append(reference) }
            default:
                break
            }
        }

        func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
            switch elementName {
            case "TestAction": inTestAction = false
            case "TestableReference": inTestableReference = false
            default: break
            }
        }
    }

    // MARK: - Files

    private func xctestrunTargets(
        xcodebuildArguments: [String],
        derivedDataPath: AbsolutePath?
    ) async throws -> [String: String] {
        var targets: [String: String] = [:]
        for path in try await xctestrunPaths(xcodebuildArguments: xcodebuildArguments, derivedDataPath: derivedDataPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path.pathString))
            for (target, parallel) in try Self.parallelizationByTarget(xctestrun: data) {
                targets[target] = parallel ? TestExecutionModes.parallel : TestExecutionModes.serial
            }
        }
        return targets
    }

    /// The xctestrun files that describe the run: the one passed with `-xctestrun`, those in the
    /// test products passed with `-testProductsPath`, or the ones xcodebuild wrote under the
    /// derived data's build products (`build-for-testing` only; a plain `test` writes none).
    private func xctestrunPaths(xcodebuildArguments: [String], derivedDataPath: AbsolutePath?) async throws -> [AbsolutePath] {
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        if let value = Self.value(of: "-xctestrun", in: xcodebuildArguments) {
            return [try AbsolutePath(validating: value, relativeTo: currentDirectory)]
        }
        if let value = Self.value(of: "-testProductsPath", in: xcodebuildArguments) {
            let products = try AbsolutePath(validating: value, relativeTo: currentDirectory)
            return try await fileSystem.glob(directory: products, include: ["**/*.xctestrun"]).collect()
        }
        guard let derivedDataPath else { return [] }
        let buildProducts = derivedDataPath.appending(components: "Build", "Products")
        guard try await fileSystem.exists(buildProducts) else { return [] }
        return try await fileSystem.glob(directory: buildProducts, include: ["*.xctestrun"]).collect()
    }

    /// The targets of the scheme named with `-scheme`, read from the shared scheme file of the
    /// `-workspace` or `-project` container (or of a project inside the workspace's directory),
    /// with its test plans' settings on top.
    private func schemeFileTargets(xcodebuildArguments: [String]) async throws -> [String: String] {
        guard let scheme = Self.value(of: "-scheme", in: xcodebuildArguments) else { return [:] }
        let currentDirectory = try await Environment.current.currentWorkingDirectory()
        let container: AbsolutePath
        if let workspace = Self.value(of: "-workspace", in: xcodebuildArguments) {
            container = try AbsolutePath(validating: workspace, relativeTo: currentDirectory)
        } else if let project = Self.value(of: "-project", in: xcodebuildArguments) {
            container = try AbsolutePath(validating: project, relativeTo: currentDirectory)
        } else {
            return [:]
        }

        let schemeFile = "xcshareddata/xcschemes/\(scheme).xcscheme"
        var candidates = [container.appending(try RelativePath(validating: schemeFile))]
        candidates += try await fileSystem.glob(
            directory: container.parentDirectory,
            include: ["*.xcodeproj/\(schemeFile)", "*/*.xcodeproj/\(schemeFile)"]
        ).collect()

        for candidate in candidates where try await fileSystem.exists(candidate) {
            let parsed = Self.parseScheme(try Data(contentsOf: URL(fileURLWithPath: candidate.pathString)))
            var targets = parsed.targets
            for reference in parsed.testPlans {
                let relative = reference.hasPrefix("container:") ? String(reference.dropFirst("container:".count)) : reference
                let planPath = container.parentDirectory.appending(try RelativePath(validating: relative))
                guard try await fileSystem.exists(planPath) else { continue }
                let plan = try Self.parseTestPlan(try Data(contentsOf: URL(fileURLWithPath: planPath.pathString)))
                targets.merge(plan) { _, new in new }
            }
            return targets
        }
        return [:]
    }

    private static func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
