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

    public func build(workspacePath: AbsolutePath,
                      target: Target,
                      into outputDirectory: AbsolutePath) throws
    {
        try build(.workspace(workspacePath),
                  target: target,
                  into: outputDirectory)
    }

    public func build(projectPath: AbsolutePath,
                      target: Target,
                      into outputDirectory: AbsolutePath) throws
    {
        try build(.project(projectPath),
                  target: target,
                  into: outputDirectory)
    }

    // MARK: - Fileprivate

    // swiftlint:disable:next function_body_length
    fileprivate func build(_ projectTarget: XcodeBuildTarget,
                           target: Target,
                           into outputDirectory: AbsolutePath) throws
    {
        guard target.product.isFramework else {
            throw CacheBinaryBuilderError.nonFrameworkTargetForXCFramework(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        return try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            logger.notice("Building .xcframework for \(target.name)...", metadata: .section)

            // Build for the simulator
            var simulatorArchivePath: AbsolutePath?
            if target.platform.hasSimulators {
                simulatorArchivePath = temporaryDirectory.appending(component: "simulator.xcarchive")
                try simulatorBuild(
                    projectTarget: projectTarget,
                    scheme: scheme,
                    target: target,
                    archivePath: simulatorArchivePath!
                )
            }

            // Build for the device - if required
            let deviceArchivePath = temporaryDirectory.appending(component: "device.xcarchive")
            try deviceBuild(
                projectTarget: projectTarget,
                scheme: scheme,
                target: target,
                archivePath: deviceArchivePath
            )

            // Build the xcframework
            var frameworkpaths = [AbsolutePath]()
            if let simulatorArchivePath = simulatorArchivePath {
                frameworkpaths.append(frameworkPath(fromArchivePath: simulatorArchivePath, productName: target.productName))
            }
            frameworkpaths.append(frameworkPath(fromArchivePath: deviceArchivePath, productName: target.productName))
            let xcframeworkPath = outputDirectory.appending(component: "\(target.productName).xcframework")
            try buildXCFramework(frameworks: frameworkpaths, output: xcframeworkPath, target: target)

            try FileHandler.shared.move(from: xcframeworkPath, to: outputDirectory.appending(component: xcframeworkPath.basename))
        }
    }

    fileprivate func buildXCFramework(frameworks: [AbsolutePath], output: AbsolutePath, target: Target) throws {
        _ = try xcodeBuildController.createXCFramework(frameworks: frameworks, output: output)
            .do(onSubscribed: {
                logger.notice("Exporting xcframework for \(target.platform.caseValue)", metadata: .subsection)
            })
            .toBlocking()
            .last()
    }

    fileprivate func deviceBuild(projectTarget: XcodeBuildTarget,
                                 scheme: String,
                                 target: Target,
                                 archivePath: AbsolutePath) throws
    {
        // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
        _ = try xcodeBuildController.archive(projectTarget,
                                             scheme: scheme,
                                             clean: false,
                                             archivePath: archivePath,
                                             arguments: [
                                                 .sdk(target.platform.xcodeDeviceSDK),
                                                 .xcarg("SKIP_INSTALL", "NO"),
                                                 .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                             ])
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) for device...", metadata: .subsection)
            })
            .ignoreElements()
            .toBlocking()
            .last()
    }

    fileprivate func simulatorBuild(projectTarget: XcodeBuildTarget,
                                    scheme: String,
                                    target: Target,
                                    archivePath: AbsolutePath) throws
    {
        // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
        _ = try xcodeBuildController.archive(projectTarget,
                                             scheme: scheme,
                                             clean: false,
                                             archivePath: archivePath,
                                             arguments: [
                                                 .sdk(target.platform.xcodeSimulatorSDK!),
                                                 .xcarg("SKIP_INSTALL", "NO"),
                                                 .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                             ])
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) for simulator...", metadata: .subsection)
            })
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
