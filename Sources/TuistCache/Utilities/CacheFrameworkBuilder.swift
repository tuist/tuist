import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport

public final class CacheFrameworkBuilder: CacheArtifactBuilding {
    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    /// Simulator controller.
    private let simulatorController: SimulatorControlling

    /// Developer's environment.
    private let developerEnvironment: DeveloperEnvironmenting

    /// Locator for getting Xcode build directory.
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating

    // MARK: - Init

    /// Initialzies the builder.
    /// - Parameters:
    ///   - xcodeBuildController: Xcode build controller.
    ///   - simulatorController: Simulator controller.
    ///   - developerEnvironment: Developer environment.
    ///   - xcodeProjectBuildDirectoryLocator: Locator for Xcode builds.
    public init(
        xcodeBuildController: XcodeBuildControlling,
        simulatorController: SimulatorControlling = SimulatorController(),
        developerEnvironment: DeveloperEnvironmenting = DeveloperEnvironment.shared,
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator()
    ) {
        self.xcodeBuildController = xcodeBuildController
        self.simulatorController = simulatorController
        self.developerEnvironment = developerEnvironment
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
    }

    // MARK: - ArtifactBuilding

    /// Returns the type of artifact that the concrete builder processes
    public var cacheOutputType: CacheOutputType = .framework

    public func build(
        graph _: Graph,
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
            version: osVersion,
            deviceName: deviceName
        )

        try await xcodeBuildController.build(
            projectTarget,
            scheme: scheme.name,
            destination: nil,
            clean: false,
            arguments: arguments
        ).printFormattedOutput()

        let buildDirectory = try xcodeProjectBuildDirectoryLocator.locate(
            platform: platform,
            projectPath: projectTarget.path,
            configuration: configuration
        )

        try exportFrameworksAndDSYMs(
            from: buildDirectory,
            into: outputDirectory
        )
    }

    // MARK: - Fileprivate

    fileprivate func arguments(
        platform: Platform,
        configuration: String,
        version: Version?,
        deviceName: String?
    ) async throws -> [XcodeBuildArgument] {
        let destination = try await simulatorController
            .destination(for: platform, version: version, deviceName: deviceName)
        return [
            .configuration(configuration),
            .xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
            .xcarg("GCC_GENERATE_DEBUGGING_SYMBOLS", "YES"),
            .destination(destination),
        ]
    }

    fileprivate func exportFrameworksAndDSYMs(
        from buildDirectory: AbsolutePath,
        into outputDirectory: AbsolutePath
    ) throws {
        let frameworks = FileHandler.shared.glob(buildDirectory, glob: "*.framework")
        try frameworks.forEach { framework in
            try FileHandler.shared.copy(from: framework, to: outputDirectory.appending(component: framework.basename))
        }

        let dsyms = FileHandler.shared.glob(buildDirectory, glob: "*.dSYM")
        try dsyms.forEach { dsym in
            try FileHandler.shared.copy(from: dsym, to: outputDirectory.appending(component: dsym.basename))
        }
    }
}
