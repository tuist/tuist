import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import struct TSCUtility.Version
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

    public func build(
        scheme: Scheme,
        projectTarget: XcodeBuildTarget,
        configuration: String,
        osVersion: Version?,
        deviceName: String?,
        into outputDirectory: AbsolutePath
    ) async throws {
        let platform = self.platform(scheme: scheme)

        let arguments = try await self.arguments(
            platform: platform,
            configuration: configuration,
            osVersion: osVersion,
            deviceName: deviceName
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
                               configuration: String,
                               osVersion: Version?,
                               deviceName: String?) async throws -> [XcodeBuildArgument]
    {
        let destination = try await simulatorController.destination(
            for: platform,
            version: osVersion,
            deviceName: deviceName
        )

        return [
            .sdk(platform == .macOS ? platform.xcodeDeviceSDK : platform.xcodeSimulatorSDK!),
            .configuration(configuration),
            .destination(destination),
        ]
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
