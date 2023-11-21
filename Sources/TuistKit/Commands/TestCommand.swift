import AnyCodable
import ArgumentParser
import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Command that tests a target from the project in the current directory.
public struct TestCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}

    public static var analyticsDelegate: TrackableParametersDelegate?

    public static var configuration: CommandConfiguration {
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
        help: "Test on a specific platform."
    )
    var platform: String?

    @Option(
        name: .shortAndLong,
        help: "Test with a specific version of the OS."
    )
    var os: String?

    @Flag(
        name: .long,
        help: "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode."
    )
    var rosetta: Bool = false

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
        help: "Overrides the folder that should be used for derived data when testing a project."
    )
    var derivedDataPath: String?

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

    public func validate() throws {
        try TestService().validateParameters(
            testTargets: testTargets,
            skipTestTargets: skipTestTargets
        )
    }

    public func run() async throws {
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
            validateTestTargetsParameters: false
        )
    }
}
