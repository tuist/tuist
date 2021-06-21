import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public enum CacheBundleBuilderError: FatalError {
    case builtProductsDirectoryNotFound(targetName: String)
    case bundleNotFound(name: String, derivedDataPath: AbsolutePath)
    case deviceNotFound(platform: String)

    public var description: String {
        switch self {
        case let .builtProductsDirectoryNotFound(targetName):
            return "Couldn't find the built products directory for target '\(targetName)'."
        case let .bundleNotFound(name, derivedDataPath):
            return "Couldn't find bundle '\(name)' in the derived data directory: \(derivedDataPath.pathString)"
        case let .deviceNotFound(platform):
            return "Couldn't find an available device for platform: '\(platform)'"
        }
    }

    public var type: ErrorType {
        switch self {
        case .builtProductsDirectoryNotFound: return .bug
        case .bundleNotFound: return .bug
        case .deviceNotFound: return .bug
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

    public func build(workspacePath: AbsolutePath, target: Target, configuration: String, into outputDirectory: AbsolutePath) throws {
        try build(
            .workspace(workspacePath),
            target: target,
            configuration: configuration,
            into: outputDirectory
        )
    }
    
    public func build(projectPath: AbsolutePath, target: Target, configuration: String, into outputDirectory: AbsolutePath) throws {
        try build(
            .project(projectPath),
            target: target,
            configuration: configuration,
            into: outputDirectory
        )
    }

    fileprivate func build(_ projectTarget: XcodeBuildTarget,
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

    fileprivate func sdk(target: Target) -> String {
        if target.platform == .macOS {
            return target.platform.xcodeDeviceSDK
        } else {
            return target.platform.xcodeSimulatorSDK!
        }
    }

    fileprivate func arguments(target: Target,
                               sdk: String,
                               configuration: String) throws -> [XcodeBuildArgument]
    {
        try destination(target: target)
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

    fileprivate func destination(target: Target) -> Single<String> {
        var platform: Platform!
        switch target.platform {
        case .iOS: platform = .iOS
        case .watchOS: platform = .watchOS
        case .tvOS: platform = .tvOS
        case .macOS: return .just("platform=OS X,arch=x86_64")
        }

        return simulatorController.findAvailableDevice(platform: platform)
            .flatMap { (deviceAndRuntime) -> Single<String> in
                .just("id=\(deviceAndRuntime.device.udid)")
            }
    }

    fileprivate func xcodebuild(projectTarget: XcodeBuildTarget,
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

    fileprivate func exportBundle(from buildDirectory: AbsolutePath,
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
