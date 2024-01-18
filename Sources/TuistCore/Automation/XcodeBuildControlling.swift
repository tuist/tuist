import Foundation
import TSCBasic
import TuistSupport

public enum XcodeBuildDestination: Equatable {
    case device(String)
    case mac
}

/// An enum that represents value pairs that can be passed when creating an .xcframework.
public enum XcodeBuildControllerCreateXCFrameworkArgument {
    /**
     An argument that represents a framework archive. The argument is a tuple containing the
     absolute path to the archive, and the name of the framework inside the archive.

     xcodebuild -create-xcframework
         -archive archives/MyFramework-iOS.xcarchive -framework MyFramework.framework
         -archive archives/MyFramework-iOS_Simulator.xcarchive -framework MyFramework.framework
         -archive archives/MyFramework-macOS.xcarchive -framework MyFramework.framework
         -archive archives/MyFramework-Mac_Catalyst.xcarchive -framework MyFramework.framework
         -output xcframeworks/MyFramework.xcframework
     */
    case framework(archivePath: AbsolutePath, framework: String)

    /**
     An argument that represents a library. The argument is a tuple containing the absolute path
     to the library, and the absolute path to the directory containing the headers.

     xcodebuild -create-xcframework
         -library products/iOS/usr/local/lib/libMyLibrary.a -headers products/iOS/usr/local/include
         -library products/iOS_Simulator/usr/local/lib/libMyLibrary.a -headers products/iOS/usr/local/include
         -library products/macOS/usr/local/lib/libMyLibrary.a -headers products/macOS/usr/local/include
         -library products/Mac\ Catalyst/usr/local/lib/libMyLibrary.a -headers products/Mac\ Catalyst/usr/local/include
         -output xcframeworks/MyLibrary.xcframework
     */
    case library(path: AbsolutePath, headers: AbsolutePath)

    /**
     Returns the arguments that represent his argument when invoking xcodebuild.
     */
    public var xcodebuildArguments: [String] {
        func sanitizedPath(_ path: AbsolutePath) -> String {
            // It's workaround for Xcode 15 RC bug
            // remove it since bug will be fixed
            // more details here: https://github.com/tuist/tuist/issues/5354
            path.pathString.hasPrefix("/var/") ? path.pathString.replacingOccurrences(of: "/var/", with: "/private/var/") : path
                .pathString
        }
        switch self {
        case let .framework(archivePath, framework):
            return ["-archive", sanitizedPath(archivePath), "-framework", framework]
        case let .library(libraryPath, headers):
            return ["-library", sanitizedPath(libraryPath), "-headers", sanitizedPath(headers)]
        }
    }
}

public protocol XcodeBuildControlling {
    /// Returns an observable to build the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be built.
    ///   - scheme: The scheme of the project that should be built.
    ///   - destination: The optional destination to build on. Omitting this will allow `xcodebuild`
    ///   to determine the destination.
    ///   - clean: True if xcodebuild should clean the project before building.
    ///   - arguments: Extra xcodebuild arguments.
    func build(
        _ target: XcodeBuildTarget,
        scheme: String,
        destination: XcodeBuildDestination?,
        rosetta: Bool,
        derivedDataPath: AbsolutePath?,
        clean: Bool,
        arguments: [XcodeBuildArgument]
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>

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
        testPlanConfiguration: TestPlanConfiguration?
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>

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
    ) throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>

    /// Creates an .xcframework combining the list of given frameworks.
    /// - Parameters:
    ///   - arguments: A set of arguments to configure the XCFramework creation.
    ///   - output: Path to the output .xcframework.
    func createXCFramework(
        arguments: [XcodeBuildControllerCreateXCFrameworkArgument],
        output: AbsolutePath
    )
        throws -> AsyncThrowingStream<SystemEvent<XcodeBuildOutput>, Error>

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
