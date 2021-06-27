import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum CacheBundleBuilderError: FatalError {
    case bundleNotFound(name: String, derivedDataPath: AbsolutePath)

    var description: String {
        switch self {
        case let .bundleNotFound(name, derivedDataPath):
            return "Couldn't find bundle '\(name)' in the derived data directory: \(derivedDataPath.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .bundleNotFound: return .bug
        }
    }
}

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

    public func build(projectTarget: XcodeBuildTarget,
                      target: Target,
                      configuration: String,
                      into outputDirectory: AbsolutePath) throws
    {
        guard target.product == .bundle else {
            throw CacheBinaryBuilderError.nonBundleTarget(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        logger.notice("Building .bundle for \(target.name)...", metadata: .section)

        let sdk = self.sdk(target: target)

        let arguments = try self.arguments(
            target: target,
            sdk: sdk,
            configuration: configuration
        )

        try xcodebuild(
            projectTarget: projectTarget,
            scheme: scheme,
            target: target,
            arguments: arguments
        )

        let buildDirectory = try xcodeProjectBuildDirectoryLocator.locate(
            platform: target.platform,
            projectPath: projectTarget.path,
            configuration: configuration
        )

        try exportBundle(
            from: buildDirectory,
            into: outputDirectory,
            target: target
        )
    }

    private func sdk(target: Target) -> String {
        if target.platform == .macOS {
            return target.platform.xcodeDeviceSDK
        } else {
            return target.platform.xcodeSimulatorSDK!
        }
    }

    private func arguments(target: Target,
                           sdk: String,
                           configuration: String) throws -> [XcodeBuildArgument]
    {
        try simulatorController.destination(for: target.platform)
            .map { (destination: String) -> [XcodeBuildArgument] in
                [
                    .sdk(sdk),
                    .configuration(configuration),
                    .destination(destination),
                ]
            }
            .toBlocking()
            .single()
    }

    private func xcodebuild(projectTarget: XcodeBuildTarget,
                            scheme: String,
                            target: Target,
                            arguments: [XcodeBuildArgument]) throws
    {
        _ = try xcodeBuildController.build(
            projectTarget,
            scheme: scheme,
            clean: false,
            arguments: arguments
        )
        .printFormattedOutput()
        .do(onSubscribed: {
            logger.notice("Building \(target.name) as .bundle...", metadata: .subsection)
        })
        .ignoreElements()
        .toBlocking()
        .last()
    }

    private func exportBundle(from buildDirectory: AbsolutePath,
                              into outputDirectory: AbsolutePath,
                              target: Target) throws
    {
        logger.info("Exporting built \(target.name) bundle...")

        guard let bundle = FileHandler.shared.glob(buildDirectory, glob: target.productNameWithExtension).first else {
            let derivedDataPath = developerEnvironment.derivedDataDirectory
            throw CacheBundleBuilderError.bundleNotFound(name: target.productNameWithExtension, derivedDataPath: derivedDataPath)
        }
        try FileHandler.shared.copy(from: bundle, to: outputDirectory.appending(component: bundle.basename))

        logger.info("Done exporting from \(target.name) into Tuist cache")
    }
}
