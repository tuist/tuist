import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public final class CacheBundleBuilder: CacheArtifactBuilding {
    public var cacheOutputType: CacheOutputType = .bundle

    private let simulatorController: SimulatorControlling
    private let xcodeBuildController: XcodeBuildControlling
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let developerEnvironment: DeveloperEnvironmenting

    public init(
        xcodeBuildController: XcodeBuildControlling,
        simulatorController: SimulatorControlling = SimulatorController(),
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
        developerEnvironment: DeveloperEnvironmenting = DeveloperEnvironment.shared
    ) {
        self.simulatorController = simulatorController
        self.xcodeBuildController = xcodeBuildController
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.developerEnvironment = developerEnvironment
    }

    public func build(scheme: Scheme, projectTarget: XcodeBuildTarget, configuration: String, into outputDirectory: AbsolutePath) throws {
        let platform = self.platform(scheme: scheme)

        let arguments = try self.arguments(
            platform: platform,
            configuration: configuration
        )

        try xcodebuild(
            projectTarget: projectTarget,
            scheme: scheme.name,
            arguments: arguments
        )

        let buildDirectory = try xcodeProjectBuildDirectoryLocator.locate(
            platform: platform,
            projectPath: projectTarget.path,
            configuration: configuration
        )

        try exportBundles(
            from: buildDirectory,
            into: outputDirectory
        )
    }

    // MARK: - Fileprivate

    fileprivate func arguments(platform: Platform,
                               configuration: String) throws -> [XcodeBuildArgument]
    {
        return try simulatorController.destination(for: platform)
            .map { (destination: String) -> [XcodeBuildArgument] in
                [
                    .sdk(platform == .macOS ? platform.xcodeDeviceSDK : platform.xcodeSimulatorSDK!),
                    .configuration(configuration),
                    .destination(destination),
                ]
            }
            .toBlocking()
            .single()
    }

    fileprivate func xcodebuild(projectTarget: XcodeBuildTarget,
                                scheme: String,
                                arguments: [XcodeBuildArgument]) throws
    {
        _ = try xcodeBuildController.build(
            projectTarget,
            scheme: scheme,
            clean: false,
            arguments: arguments
        )
        .printFormattedOutput()
        .ignoreElements()
        .toBlocking()
        .last()
    }

    fileprivate func exportBundles(from buildDirectory: AbsolutePath,
                                   into outputDirectory: AbsolutePath) throws
    {
        let bundles = FileHandler.shared.glob(buildDirectory, glob: "*.bundle")
        try bundles.forEach { bundle in
            try FileHandler.shared.copy(from: bundle, to: outputDirectory.appending(component: bundle.basename))
        }
    }
}
