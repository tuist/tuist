import AnyCodable
import ArgumentParser
import Foundation
import TSCBasic
import TuistCore
import TuistSupport
#if canImport(TuistCloud)
    import TuistCloud
#endif

/// Command that tests a target from the project in the current directory.
struct TestCommand: AsyncParsableCommand, HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate?

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project"
        )
    }

    @Argument(
        help: "The scheme to be tested. By default it tests all the testable targets of the project in the current directory."
    )
    var scheme: String?

    @Flag(
        name: .shortAndLong,
        help: "When passed, it cleans the project before testing it."
    )
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be tested."
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "Test on a specific device."
    )
    var device: String?

    @Option(
        name: .shortAndLong,
        help: "Test with a specific version of the OS."
    )
    var os: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when testing the scheme."
    )
    var configuration: String?

    @Flag(
        name: .long,
        help: "When passed, it skips testing UI Tests targets."
    )
    var skipUITests: Bool = false

    @Option(
        name: [.long, .customShort("T")],
        help: "Path where test result bundle will be saved."
    )
    var resultBundlePath: String?

    @Option(
        name: .long,
        help: "Tests will retry <number> of times until success. Example: if 1 is specified, the test will be retried at most once, hence it will run up to 2 times."
    )
    var retryCount: Int = 0

    @Option(
        name: .long,
        help: "The test plan to run."
    )
    var testPlan: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to test. Expected format is TestTarget[/TestClass[/TestMethod]]. It is applied before --skip-testing",
        transform: TestIdentifier.init(string:)
    )
    var testTargets: [TestIdentifier] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of test identifiers you want to skip testing. Expected format is TestTarget[/TestClass[/TestMethod]].",
        transform: TestIdentifier.init(string:)
    )
    var skipTestTargets: [TestIdentifier] = []

    @Option(
        name: .customLong("filter-configurations"),
        parsing: .upToNextOption,
        help: "The list of configurations you want to test. It is applied before --skip-configuration"
    )
    var configurations: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "The list of configurations you want to skip testing."
    )
    var skipConfigurations: [String] = []

    @Flag(
        name: [.customShort("x"), .long],
        help: "When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator)."
    )
    var xcframeworks: Bool = false

    @Option(
        name: [.long],
        help: "Type of cached xcframeworks to use when --xcframeworks is passed (device/simulator)",
        completion: .list(["device", "simulator"])
    )
    var destination: CacheXCFrameworkDestination = [.device, .simulator]

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the cache profile to be used when testing."
    )
    var profile: String?

    @Flag(
        name: [.customLong("no-cache")],
        help: "Ignore cached targets, and use their sources instead."
    )
    var ignoreCache: Bool = false

    @Option(
        name: [.customLong("skip-cache")],
        help: "A list of targets which will not use cached binaries when using default `sources` list."
    )
    var targetsToSkipCache: [String] = []

    func validate() throws {
        try TestService().validateParameters(
            testTargets: testTargets,
            skipTestTargets: skipTestTargets
        )
    }

    // swiftlint:disable:next function_body_length
    func run() async throws {
        let absolutePath: AbsolutePath

        if let path {
            absolutePath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try await TestService().run(
            schemeName: scheme,
            clean: clean,
            configuration: configuration,
            path: absolutePath,
            deviceName: device,
            osVersion: os,
            skipUITests: skipUITests,
            resultBundlePath: resultBundlePath.map {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: FileHandler.shared.currentPath
                )
            },
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
            xcframeworks: xcframeworks,
            destination: destination,
            profile: profile,
            ignoreCache: ignoreCache,
            targetsToSkipCache: Set(targetsToSkipCache)
        )
        var parameters: [String: AnyCodable] = [
            "xcframeworks": AnyCodable(xcframeworks),
            "no_cache": AnyCodable(ignoreCache),
        ]
        #if canImport(TuistCloud)
            parameters["cacheable_targets"] = AnyCodable(CacheAnalytics.cacheableTargets)
            parameters["local_cache_target_hits"] = AnyCodable(CacheAnalytics.localCacheTargetsHits)
            parameters["remote_cache_target_hits"] = AnyCodable(CacheAnalytics.remoteCacheTargetsHits)
        #endif
        TestCommand.analyticsDelegate?.addParameters(
            [
                "xcframeworks": AnyCodable(xcframeworks),
                "no_cache": AnyCodable(ignoreCache),
            ]
        )
    }
}
