import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistSupport

public final class CacheXCFrameworkBuilder: CacheArtifactBuilding {
    public enum BuilderError: LocalizedError {
        case buildDestinationUnavailable

        public var errorDescription: String? {
            switch self {
            case .buildDestinationUnavailable:
                return "Neither simulator nor device build destination is available"
            }
        }
    }

    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    // MARK: - Init

    /// Initializes the builder.
    /// - Parameter xcodeBuildController: Xcode build controller instance to run xcodebuild commands.
    /// - Parameter destination: Output type of xcframework (device and/or simulator)
    public init(xcodeBuildController: XcodeBuildControlling, destination: CacheXCFrameworkDestination) {
        self.xcodeBuildController = xcodeBuildController
        self.cacheOutputType = .xcframework(destination)
    }

    // MARK: - ArtifactBuilding

    /// Returns the type of artifact that the concrete builder processes
    public var cacheOutputType: CacheOutputType

    public func build(
        scheme: Scheme,
        projectTarget: XcodeBuildTarget,
        configuration: String,
        osVersion _: Version?,
        deviceName _: String?,
        into outputDirectory: AbsolutePath
    ) async throws {
        let platform = self.platform(scheme: scheme)

        // Create temporary directories
        return try await FileHandler.shared.inTemporaryDirectory { temporaryDirectory in

            // Build for the simulator - if required
            var simulatorArchivePath: AbsolutePath?
            if platform.hasSimulators, self.cacheOutputType.shouldBuildForSimulator {
                simulatorArchivePath = temporaryDirectory.appending(component: "simulator.xcarchive")
                try await self.simulatorBuild(
                    projectTarget: projectTarget,
                    scheme: scheme.name,
                    platform: platform,
                    configuration: configuration,
                    archivePath: simulatorArchivePath!
                )
            }

            // Build for the device - if required
            var deviceArchivePath: AbsolutePath?
            if self.cacheOutputType.shouldBuildForDevice {
                deviceArchivePath = temporaryDirectory.appending(component: "device.xcarchive")
                try await self.deviceBuild(
                    projectTarget: projectTarget,
                    scheme: scheme.name,
                    platform: platform,
                    configuration: configuration,
                    archivePath: deviceArchivePath!
                )
            }

            try await self.createXCFramework(
                simulatorArchivePath: simulatorArchivePath,
                deviceArchivePath: deviceArchivePath,
                outputDirectory: outputDirectory
            )
        }
    }

    // MARK: - Fileprivate

    fileprivate func createXCFramework(
        simulatorArchivePath: AbsolutePath?,
        deviceArchivePath: AbsolutePath?,
        outputDirectory: AbsolutePath
    ) async throws {
        let archivePath: AbsolutePath

        if let deviceArchivePath = deviceArchivePath {
            archivePath = deviceArchivePath
        } else if let simulatorArchivePath = simulatorArchivePath {
            archivePath = simulatorArchivePath
        } else {
            throw BuilderError.buildDestinationUnavailable
        }

        let productNames = archivePath
            .appending(RelativePath("Products/Library/Frameworks/"))
            .glob("*.framework")
            .map(\.basenameWithoutExt)

        // Build the xcframework
        for productName in productNames {
            var frameworkpaths = [AbsolutePath]()
            if let simulatorArchivePath = simulatorArchivePath {
                frameworkpaths.append(self.frameworkPath(
                    fromArchivePath: simulatorArchivePath,
                    productName: productName
                ))
            }
            if let deviceArchivePath = deviceArchivePath {
                frameworkpaths.append(self.frameworkPath(
                    fromArchivePath: deviceArchivePath,
                    productName: productName
                ))
            }
            let xcframeworkPath = outputDirectory.appending(component: "\(productName).xcframework")
            try await self.xcodeBuildController.createXCFramework(
                frameworks: frameworkpaths,
                output: xcframeworkPath
            )
            .printFormattedOutput()

            try FileHandler.shared.move(
                from: xcframeworkPath,
                to: outputDirectory.appending(component: xcframeworkPath.basename)
            )
        }
    }

    fileprivate func deviceBuild(
        projectTarget: XcodeBuildTarget,
        scheme: String,
        platform: Platform,
        configuration: String,
        archivePath: AbsolutePath
    ) async throws {
        try await xcodeBuildController.archive(
            projectTarget,
            scheme: scheme,
            clean: false,
            archivePath: archivePath,
            arguments: [
                .sdk(platform.xcodeDeviceSDK),
                .xcarg("SKIP_INSTALL", "NO"),
                .configuration(configuration),
            ]
        ).printFormattedOutput()
    }

    fileprivate func simulatorBuild(
        projectTarget: XcodeBuildTarget,
        scheme: String,
        platform: Platform,
        configuration: String,
        archivePath: AbsolutePath
    ) async throws {
        try await xcodeBuildController.archive(
            projectTarget,
            scheme: scheme,
            clean: false,
            archivePath: archivePath,
            arguments: [
                .sdk(platform.xcodeSimulatorSDK!),
                .xcarg("SKIP_INSTALL", "NO"),
                .configuration(configuration),
            ]
        ).printFormattedOutput()
    }

    /// Returns the path to the framework inside the archive.
    /// - Parameters:
    ///   - archivePath: Path to the .xcarchive.
    ///   - productName: Product name.
    fileprivate func frameworkPath(fromArchivePath archivePath: AbsolutePath, productName: String) -> AbsolutePath {
        archivePath.appending(RelativePath("Products/Library/Frameworks/\(productName).framework"))
    }
}

extension CacheOutputType {
    fileprivate var shouldBuildForSimulator: Bool {
        switch self {
        case .bundle:
            return false
        case .framework:
            return true
        case let .xcframework(destination):
            return destination.contains(.simulator)
        }
    }

    fileprivate var shouldBuildForDevice: Bool {
        switch self {
        case .bundle, .framework:
            return false
        case let .xcframework(destination):
            return destination.contains(.device)
        }
    }
}
