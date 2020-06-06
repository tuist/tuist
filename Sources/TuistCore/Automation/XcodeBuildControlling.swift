import Foundation
import RxSwift
import TSCBasic
import TuistSupport

public protocol XcodeBuildControlling {
    /// Returns an observable to build the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be built.
    ///   - scheme: The scheme of the project that should be built.
    ///   - clean: True if xcodebuild should clean the project before building.
    ///   - arguments: Extra xcodebuild arguments.
    func build(_ target: XcodeBuildTarget,
               scheme: String,
               clean: Bool,
               arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>

    /// Returns an observable that archives the given project using xcodebuild.
    /// - Parameters:
    ///   - target: The project or workspace to be archived.
    ///   - scheme: The scheme of the project that should be archived.
    ///   - clean: True if xcodebuild should clean the project before archiving.
    ///   - archivePath: Path where the archive will be exported (with extension .xcarchive)
    ///   - arguments: Extra xcodebuild arguments.
    func archive(_ target: XcodeBuildTarget,
                 scheme: String,
                 clean: Bool,
                 archivePath: AbsolutePath,
                 arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>

    /// Creates an .xcframework combining the list of given frameworks.
    /// - Parameters:
    ///   - frameworks: Frameworks to be combined.
    ///   - output: Path to the output .xcframework.
    func createXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>>

    /// Gets the build settings of a scheme targets.
    /// - Parameters:
    ///   - target: Project of workspace where the scheme is defined.
    ///   - scheme: Scheme whose target build settings will be obtained.
    ///   - configuration: Build configuration.
    func showBuildSettings(_ target: XcodeBuildTarget,
                           scheme: String,
                           configuration: String) -> Single<[String: XcodeBuildSettings]>
}
