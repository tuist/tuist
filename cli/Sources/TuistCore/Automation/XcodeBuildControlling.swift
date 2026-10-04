import Mockable
import Path
import XcodeGraph

public enum XcodeBuildDestination: Equatable {
    case device(String)
    case mac
    case macCatalyst
}

public enum XcodeBuildTestAction: Equatable {
    case test
    case build
    case testWithoutBuilding

    public var description: String {
        switch self {
        case .test:
            "Testing"
        case .build:
            "Building"
        case .testWithoutBuilding:
            "Testing without building"
        }
    }
}

/// Environment variables for the xcodebuild invocations made inside a task, on top of the
/// process's own: what reaches a test host through the `TEST_RUNNER_` prefix. Task-local so a
/// caller scopes it to one invocation without every `XcodeBuildControlling` method carrying it.
public enum XcodeBuildEnvironment {
    @TaskLocal public static var additionalVariables: [String: String] = [:]
}

@Mockable
public protocol XcodeBuildControlling {
    /// Returns an observable to build the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be built.
    ///   - scheme: The scheme of the project that should be built.
    ///   - destination: The optional destination to build on. Omitting this will allow `xcodebuild`
    ///   to determine the destination.
    ///   - clean: True if xcodebuild should clean the project before building.
    ///   - arguments: Extra xcodebuild arguments.
    ///   - passthroughXcodeBuildArguments: Passthrough xcodebuild arguments.
    func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        clean: Bool,
        arguments: [XcodeBuildArgument],
        passthroughXcodeBuildArguments: [String]
    ) async throws

    /// Returns an observable to test the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be built.
    ///   - scheme: The scheme of the project that should be built.
    ///   - clean: True if xcodebuild should clean the project before building.
    ///   - destination: Destination to run the tests on
    ///   - derivedDataPath: Custom location for derived data. Use `xcodebuild`'s default if `nil`
    ///   - resultBundlePath: Path where test result bundle will be saved.
    ///   - arguments: Extra xcodebuild arguments.
    ///   - testTargets: A list of test identifiers indicating which tests to run
    ///   - skipTestTargets: A list of test identifiers indicating which tests to skip
    ///   - testPlanConfiguration: A configuration object indicating which test plan to use and its configurations
    ///   - passthroughXcodeBuildArguments: Passthrough xcodebuild arguments.
    func test(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        destination: XcodeBuildDestination?,
        action: XcodeBuildTestAction,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        resultBundlePath: AbsolutePath?,
        arguments: [XcodeBuildArgument],
        retryCount: Int,
        testTargets: [TestIdentifier],
        skipTestTargets: [TestIdentifier],
        testPlanConfiguration: TestPlanConfiguration?,
        passthroughXcodeBuildArguments: [String]
    ) async throws

    /// Returns an observable that archives the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be archived.
    ///   - scheme: The scheme of the project that should be archived.
    ///   - clean: True if xcodebuild should clean the project before archiving.
    ///   - archivePath: Path where the archive will be exported (with extension .xcarchive)
    ///   - arguments: Extra xcodebuild arguments.
    ///   - derivedDataPath: Custom location for derived data. Use `xcodebuild`'s default if `nil`
    func archive(
        _ target: XcodeBuildTarget,
        scheme: String,
        clean: Bool,
        archivePath: AbsolutePath,
        arguments: [XcodeBuildArgument],
        derivedDataPath: AbsolutePath?
    ) async throws

    /// Creates an .xcframework combining the list of given frameworks.
    /// - Parameters:
    ///   - arguments: A set of arguments to configure the XCFramework creation.
    ///   - output: Path to the output .xcframework.
    func createXCFramework(
        arguments: [String],
        output: AbsolutePath
    ) async throws

    /// Gets the build settings of a scheme targets.
    /// - Parameters:
    ///   - target: Project of workspace where the scheme is defined.
    ///   - scheme: Scheme whose target build settings will be obtained.
    ///   - configuration: Build configuration.
    ///   - derivedDataPath: Custom location for derived data. Use `xcodebuild`'s default if `nil`
    func showBuildSettings(
        _ target: XcodeBuildTarget,
        scheme: String,
        configuration: String,
        derivedDataPath: AbsolutePath?
    ) async throws -> [String: XcodeBuildSettings]

    /// Lists the tests a run with these arguments could execute, without running any
    /// (`-enumerate-tests`), as xcodebuild's flat JSON at `outputPath`. The products must be built
    /// already. The run's own filters and its result bundle are left out, so the list is every
    /// candidate rather than the ones a selective run chose.
    /// - Parameters:
    ///   - target: The project or workspace, or nil when the passthrough arguments name it.
    ///   - scheme: The scheme, or nil when the passthrough arguments name it or an xctestrun.
    func enumerateTests(
        _ target: XcodeBuildTarget?,
        scheme: String?,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        testPlan: String?,
        passthroughXcodeBuildArguments: [String],
        outputPath: AbsolutePath
    ) async throws

    /// Runs `xcodebuild` with passed `arguments` and formats the output
    /// - arguments: Arguments to pass to `xcodebuild`
    func run(arguments: [String]) async throws

    /// - Returns: `xcodebuild` version. This version is aligned with the Xcode version.
    func version() async throws -> Version?
}
