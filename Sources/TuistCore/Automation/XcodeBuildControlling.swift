import Foundation
import Mockable
import Path
import TuistSupport

public enum XcodeBuildDestination: Equatable {
    case device(String)
    case mac
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
        destination: XcodeBuildDestination,
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
}
