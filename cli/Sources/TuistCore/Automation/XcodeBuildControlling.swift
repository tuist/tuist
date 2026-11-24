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

    /// The project's compilation cache settings for an xcodebuild the CLI launches:
    /// `TUIST_CAS_ACCOUNT` and `TUIST_CAS_PROJECT` from `fullHandle`, and `TUIST_CAS_UPLOAD=false`
    /// when the project does not upload.
    ///
    /// The CAS plugin reads them in every process it loads into, including Xcode's build service,
    /// whose own cache handles get none of the `tuist-*` plugin options in the build settings. Without
    /// them, its first cache key queries name no project, and on a machine whose cache proxy has not
    /// seen the build's store (a CI host reset between jobs) they miss without asking the remote.
    /// Variables already in `environment` win.
    public static func compilationCacheVariables(
        fullHandle: String?,
        upload: Bool,
        environment: [String: String]
    ) -> [String: String] {
        var variables: [String: String] = [:]
        let handle = fullHandle?.split(separator: "/", maxSplits: 1).map(String.init) ?? []
        if handle.count == 2, environment["TUIST_CAS_ACCOUNT"] == nil, environment["TUIST_CAS_PROJECT"] == nil {
            variables["TUIST_CAS_ACCOUNT"] = handle[0]
            variables["TUIST_CAS_PROJECT"] = handle[1]
        }
        if !upload, environment["TUIST_CAS_UPLOAD"] == nil {
            variables["TUIST_CAS_UPLOAD"] = "false"
        }
        return variables
    }
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

    /// Runs `xcodebuild` with passed `arguments` and formats the output
    /// - arguments: Arguments to pass to `xcodebuild`
    func run(arguments: [String]) async throws

    /// - Returns: `xcodebuild` version. This version is aligned with the Xcode version.
    func version() async throws -> Version?
}
