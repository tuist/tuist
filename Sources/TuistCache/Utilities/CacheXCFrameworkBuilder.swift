import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public final class CacheXCFrameworkBuilder: CacheArtifactBuilding {
    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    // MARK: - Init

    /// Initializes the builder.
    /// - Parameter xcodeBuildController: Xcode build controller instance to run xcodebuild commands.
    public init(xcodeBuildController: XcodeBuildControlling) {
        self.xcodeBuildController = xcodeBuildController
    }

    // MARK: - ArtifactBuilding

    /// Returns the type of artifact that the concrete builder processes
    public var cacheOutputType: CacheOutputType = .xcframework

    public func build(scheme: Scheme, projectTarget: XcodeBuildTarget, configuration: String, into outputDirectory: AbsolutePath) throws {
        let platform = self.platform(scheme: scheme)

        // Create temporary directories
        return try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in

            // Build for the simulator
            var simulatorArchivePath: AbsolutePath?
            if platform.hasSimulators {
                simulatorArchivePath = temporaryDirectory.appending(component: "simulator.xcarchive")
                try simulatorBuild(
                    projectTarget: projectTarget,
                    scheme: scheme.name,
                    platform: platform,
                    configuration: configuration,
                    archivePath: simulatorArchivePath!
                )
            }

            // Build for the device - if required
            let deviceArchivePath = temporaryDirectory.appending(component: "device.xcarchive")
            try deviceBuild(
                projectTarget: projectTarget,
                scheme: scheme.name,
                platform: platform,
                configuration: configuration,
                archivePath: deviceArchivePath
            )

            let productNames = deviceArchivePath
                .appending(RelativePath("Products/Library/Frameworks/"))
                .glob("*")
                .map { $0.basenameWithoutExt }

            // Build the xcframework
            for productName in productNames {
                var frameworkpaths = [AbsolutePath]()
                if let simulatorArchivePath = simulatorArchivePath {
                    frameworkpaths.append(frameworkPath(fromArchivePath: simulatorArchivePath, productName: productName))
                }
                frameworkpaths.append(frameworkPath(fromArchivePath: deviceArchivePath, productName: productName))
                let xcframeworkPath = outputDirectory.appending(component: "\(productName).xcframework")
                try buildXCFramework(frameworks: frameworkpaths, output: xcframeworkPath)

                try FileHandler.shared.move(from: xcframeworkPath, to: outputDirectory.appending(component: xcframeworkPath.basename))
            }
        }
    }

    // MARK: - Fileprivate

    fileprivate func buildXCFramework(frameworks: [AbsolutePath], output: AbsolutePath) throws {
        _ = try xcodeBuildController.createXCFramework(frameworks: frameworks, output: output)
            .toBlocking()
            .last()
    }

    fileprivate func deviceBuild(projectTarget: XcodeBuildTarget,
                                 scheme: String,
                                 platform: Platform,
                                 configuration: String,
                                 archivePath: AbsolutePath) throws
    {
        _ = try xcodeBuildController.archive(
            projectTarget,
            scheme: scheme,
            clean: false,
            archivePath: archivePath,
            arguments: [
                .sdk(platform.xcodeDeviceSDK),
                .xcarg("SKIP_INSTALL", "NO"),
                .configuration(configuration),
            ]
        )
        .printFormattedOutput()
        .ignoreElements()
        .toBlocking()
        .last()
    }

    fileprivate func simulatorBuild(projectTarget: XcodeBuildTarget,
                                    scheme: String,
                                    platform: Platform,
                                    configuration: String,
                                    archivePath: AbsolutePath) throws
    {
        _ = try xcodeBuildController.archive(
            projectTarget,
            scheme: scheme,
            clean: false,
            archivePath: archivePath,
            arguments: [
                .sdk(platform.xcodeSimulatorSDK!),
                .xcarg("SKIP_INSTALL", "NO"),
                .configuration(configuration),
            ]
        )
        .printFormattedOutput()
        .ignoreElements()
        .toBlocking()
        .last()
    }

    /// Returns the path to the framework inside the archive.
    /// - Parameters:
    ///   - archivePath: Path to the .xcarchive.
    ///   - productName: Product name.
    fileprivate func frameworkPath(fromArchivePath archivePath: AbsolutePath, productName: String) -> AbsolutePath {
        archivePath.appending(RelativePath("Products/Library/Frameworks/\(productName).framework"))
    }
}
