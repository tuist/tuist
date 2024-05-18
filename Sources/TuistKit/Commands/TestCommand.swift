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
        help: "[Deprecated] When passed, it cleans the project before testing it."
    )
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be tested."
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "[Deprecated] Test on a specific device."
    )
    var device: String?

    @Option(
        name: .long,
        help: "[Deprecated] Test on a specific platform."
    )
    var platform: String?

    @Option(
        name: .shortAndLong,
        help: "[Deprecated] Test with a specific version of the OS."
    )
    var os: String?

    @Flag(
        name: .long,
        help: "[Deprecated] When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode."
    )
    var rosetta: Bool = false

    @Option(
        name: [.long, .customShort("C")],
        help: "[Deprecated] The configuration to be used when testing the scheme."
    )
    var configuration: String?

    @Flag(
        name: .long,
        help: "When passed, it skips testing UI Tests targets."
    )
    var skipUITests: Bool = false

    @Option(
        name: [.long, .customShort("T")],
        help: "[Deprecated] Path where test result bundle will be saved."
    )
    var resultBundlePath: String?

    @Option(
        help: "[Deprecated] Overrides the folder that should be used for derived data when testing a project."
    )
    var derivedDataPath: String?

    @Option(
        name: .long,
        help: "[Deprecated] Tests will retry <number> of times until success. Example: if 1 is specified, the test will be retried at most once, hence it will run up to 2 times."
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
        name: .long,
        help: "When passed, it generates the project and skips testing. This is useful for debugging purposes."
    )
    var generateOnly: Bool = false

    @Argument(
        parsing: .postTerminator,
        help: "xcodebuild arguments that will be passthrough"
    )
    var passthroughXcodeBuildArguments: [String] = []
    
    public func validate() throws {
        try TestService().validateParameters(
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
        "-skip-testing"
    ]

    public func run() async throws {
        // Check if passthrough arguments are already handled by tuist
        try notAllowedPassthroughXcodeBuildArguments.forEach {
            if passthroughXcodeBuildArguments.contains($0) {
                throw XcodeBuildPassthroughArgumentError.alreadyHandled($0)
            }
        }
        
        // Suggest the user to use passthrough arguments if already supported by xcodebuild
        if platform != nil || os != nil || device != nil || rosetta {
            logger.warning("--platform, --os, --device, and --rosetta are deprecated please use -destination DESTINATION after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if let configuration {
            logger.warning("--configuration is deprecated please use -configuration \(configuration) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if clean {
            logger.warning("--clean is deprecated please use clean after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if let derivedDataPath {
            logger.warning("--derivedDataPath is deprecated please use -derivedDataPath \(derivedDataPath) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if let resultBundlePath {
            logger.warning("--resultBundlePath is deprecated please use -resultBundlePath \(resultBundlePath) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if retryCount > 0 {
            logger.warning("--retryCount is deprecated please use -retry-tests-on-failure -test-iterations \(retryCount + 1) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        
        let absolutePath = if let path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
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
            validateTestTargetsParameters: false,
            generateOnly: generateOnly, 
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )
    }
}
