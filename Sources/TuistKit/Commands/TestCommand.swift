import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

/// Command that tests a target from the project in the current directory.
public struct TestCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}

    public static var analyticsDelegate: TrackableParametersDelegate?
    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
    public var runId = UUID().uuidString

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project"
        )
    }

    @Argument(
        help: "The scheme to be tested. By default it tests all the testable targets of the project in the current directory.",
        envKey: .testScheme
    )
    var scheme: String?

    @Flag(
        name: .shortAndLong,
        help: "When passed, it cleans the project before testing it.",
        envKey: .testClean
    )
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be tested.",
        completion: .directory,
        envKey: .testPath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "Test on a specific device.",
        envKey: .testDevice
    )
    var device: String?

    @Option(
        name: .long,
        help: "Test on a specific platform.",
        envKey: .testPlatform
    )
    var platform: String?

    @Option(
        name: .shortAndLong,
        help: "Test with a specific version of the OS.",
        envKey: .testOS
    )
    var os: String?

    @Flag(
        name: .long,
        help: "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode.",
        envKey: .testRosetta
    )
    var rosetta: Bool = false

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when testing the scheme.",
        envKey: .testConfiguration
    )
    var configuration: String?

    @Flag(
        name: .long,
        help: "When passed, it skips testing UI Tests targets.",
        envKey: .testSkipUITests
    )
    var skipUITests: Bool = false

    @Option(
        name: [.long, .customShort("T")],
        help: "Path where test result bundle will be saved.",
        completion: .directory,
        envKey: .testResultBundlePath
    )
    var resultBundlePath: String?

    @Option(
        help: "[Deprecated] Overrides the folder that should be used for derived data when testing a project.",
        completion: .directory,
        envKey: .testDerivedDataPath
    )
    var derivedDataPath: String?

    @Option(
        name: .long,
        help: "[Deprecated] Tests will retry <number> of times until success. Example: if 1 is specified, the test will be retried at most once, hence it will run up to 2 times.",
        envKey: .testRetryCount
    )
    var retryCount: Int = 0

    @Option(
        name: .long,
        help: "The test plan to run.",
        envKey: .testTestPlan
    )
    var testPlan: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to test. Expected format is TestTarget[/TestClass[/TestMethod]]. It is applied before --skip-testing",
        envKey: .testTestTargets
    )
    var testTargets: [TestIdentifier] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to skip testing. Expected format is TestTarget[/TestClass[/TestMethod]].",
        envKey: .testSkipTestTargets
    )
    var skipTestTargets: [TestIdentifier] = []

    @Option(
        name: .customLong("filter-configurations"),
        parsing: .upToNextOption,
        help: "The list of configurations you want to test. It is applied before --skip-configuration",
        envKey: .testConfigurations
    )
    var configurations: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of configurations you want to skip testing.",
        envKey: .testSkipConfigurations
    )
    var skipConfigurations: [String] = []

    @Flag(
        help: "Ignore binary cache and use sources only.",
        envKey: .testBinaryCache
    )
    var binaryCache: Bool = true

    @Flag(
        help: "Run all tests instead of selectively test only those that have changed since the last successful test run.",
        envKey: .testSelectiveTesting
    )
    var selectiveTesting: Bool = true

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips testing. This is useful for debugging purposes.",
        envKey: .testGenerateOnly
    )
    var generateOnly: Bool = false

    @Argument(
        parsing: .postTerminator,
        help: "xcodebuild arguments that will be passthrough"
    )
    var passthroughXcodeBuildArguments: [String] = []

    public func validate() throws {
        try TestService.validateParameters(
            testTargets: testTargets,
            skipTestTargets: skipTestTargets
        )
    }

    private var notAllowedPassthroughXcodeBuildArguments = [
        "-scheme",
        "-workspace",
        "-project",
        "-testPlan",
        "-skip-test-configuration",
        "-only-test-configuration",
        "-only-testing",
        "-skip-testing",
    ]

    public func run() async throws {
        // Check if passthrough arguments are already handled by tuist
        try notAllowedPassthroughXcodeBuildArguments.forEach {
            if passthroughXcodeBuildArguments.contains($0) {
                throw XcodeBuildPassthroughArgumentError.alreadyHandled($0)
            }
        }

        // Suggest the user to use passthrough arguments if already supported by xcodebuild
        if let derivedDataPath {
            logger
                .warning(
                    "--derivedDataPath is deprecated please use -derivedDataPath \(derivedDataPath) after the terminator (--) instead to passthrough parameters to xcodebuild"
                )
        }
        if retryCount > 0 {
            logger
                .warning(
                    "--retryCount is deprecated please use -retry-tests-on-failure -test-iterations \(retryCount + 1) after the terminator (--) instead to passthrough parameters to xcodebuild"
                )
        }

        let absolutePath = if let path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
        }

        defer {
            var parameters: [String: AnyCodable] = [
                "no_binary_cache": AnyCodable(!binaryCache),
                "no_selective_testing": AnyCodable(!selectiveTesting),
            ]
            parameters["cacheable_targets"] = AnyCodable(CacheAnalyticsStore.shared.cacheableTargets)
            parameters["local_cache_target_hits"] = AnyCodable(CacheAnalyticsStore.shared.localCacheTargetsHits)
            parameters["remote_cache_target_hits"] = AnyCodable(CacheAnalyticsStore.shared.remoteCacheTargetsHits)
            parameters["test_targets"] = AnyCodable(CacheAnalyticsStore.shared.testTargets)
            parameters["local_test_target_hits"] = AnyCodable(CacheAnalyticsStore.shared.localTestTargetHits)
            parameters["remote_test_target_hits"] = AnyCodable(CacheAnalyticsStore.shared.remoteTestTargetHits)
            parameters["target_hashes"] = AnyCodable(CacheAnalyticsStore.shared.targetHashes)
            parameters["graph_path"] = AnyCodable(CacheAnalyticsStore.shared.graphPath)

            TestCommand.analyticsDelegate?.addParameters(
                parameters
            )
        }

        try await TestService(
            generatorFactory: Self.generatorFactory,
            cacheStorageFactory: Self.cacheStorageFactory
        ).run(
            runId: runId,
            schemeName: scheme,
            clean: clean,
            configuration: configuration,
            path: absolutePath,
            deviceName: device,
            platform: platform,
            osVersion: os,
            rosetta: rosetta,
            skipUITests: skipUITests,
            resultBundlePath: resultBundlePath.map {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: FileHandler.shared.currentPath
                )
            },
            derivedDataPath: derivedDataPath,
            retryCount: retryCount,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            testPlanConfiguration: testPlan.map { testPlan in
                TestPlanConfiguration(
                    testPlan: testPlan,
                    configurations: configurations,
                    skipConfigurations: skipConfigurations
                )
            },
            validateTestTargetsParameters: false,
            ignoreBinaryCache: !binaryCache,
            ignoreSelectiveTesting: !selectiveTesting,
            generateOnly: generateOnly,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )
    }
}

extension TestIdentifier: ExpressibleByArgument {
    public init?(argument: String) {
        do {
            try self.init(string: argument)
        } catch {
            return nil
        }
    }
}
