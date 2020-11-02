import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public enum CacheFrameworkBuilderError: FatalError {
    case builtProductsDirectoryNotFound(targetName: String)
    case frameworkNotFound(name: String, derivedDataPath: AbsolutePath)
    case deviceNotFound(platform: String)

    public var description: String {
        switch self {
        case let .builtProductsDirectoryNotFound(targetName):
            return "Couldn't find the built products directory for target '\(targetName)'."
        case let .frameworkNotFound(name, derivedDataPath):
            return "Couldn't find framework '\(name)' in the derived data directory: \(derivedDataPath.pathString)"
        case let .deviceNotFound(platform):
            return "Couldn't find an available device for platform: '\(platform)'"
        }
    }

    public var type: ErrorType {
        switch self {
        case .builtProductsDirectoryNotFound: return .bug
        case .frameworkNotFound: return .bug
        case .deviceNotFound: return .bug
        }
    }
}

public final class CacheFrameworkBuilder: CacheArtifactBuilding {
    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    /// Simulator controller.
    private let simulatorController: SimulatorControlling

    /// Developer's environment.
    private let developerEnvironment: DeveloperEnvironmenting

    // MARK: - Init

    /// Initialzies the builder.
    /// - Parameters:
    ///   - xcodeBuildController: Xcode build controller.
    ///   - simulatorController: Simulator controller.
    ///   - developerEnvironment: Developer environment.
    public init(xcodeBuildController: XcodeBuildControlling,
                simulatorController: SimulatorControlling = SimulatorController(),
                developerEnvironment: DeveloperEnvironmenting = DeveloperEnvironment.shared)
    {
        self.xcodeBuildController = xcodeBuildController
        self.simulatorController = simulatorController
        self.developerEnvironment = developerEnvironment
    }

    // MARK: - ArtifactBuilding

    /// Returns the type of artifact that the concrete builder processes
    public var cacheOutputType: CacheOutputType = .framework

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

    fileprivate func build(_ projectTarget: XcodeBuildTarget,
                           target: Target,
                           into outputDirectory: AbsolutePath) throws
    {
        guard target.product.isFramework else {
            throw CacheBinaryBuilderError.nonFrameworkTargetForFramework(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        let builtProductsDirFingerprint = String.random()
        logger.notice("Building .framework for \(target.name)...", metadata: .section)

        let sdk = self.sdk(target: target)
        let configuration = "Debug" // TODO: Is it available?

        let arguments = try self.arguments(target: target,
                                           sdk: sdk,
                                           configuration: configuration,
                                           builtProductsDirFingerprint: builtProductsDirFingerprint)
        try xcodebuild(
            projectTarget: projectTarget,
            scheme: scheme,
            target: target,
            arguments: arguments
        )

        try exportFrameworksAndDSYMs(into: outputDirectory,
                                     target: target,
                                     builtProductsDirFingerprint: builtProductsDirFingerprint)
    }

    fileprivate func arguments(target: Target,
                               sdk: String,
                               configuration: String,
                               builtProductsDirFingerprint: String) throws -> [XcodeBuildArgument]
    {
        try destination(target: target)
            .map { (destination: String) -> [XcodeBuildArgument] in
                [
                    .sdk(sdk),
                    .configuration(configuration),
                    .buildSetting("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
                    .buildSetting("GCC_GENERATE_DEBUGGING_SYMBOLS", "YES"),
                    .buildSetting(target.targetLocatorBuildPhaseVariable, builtProductsDirFingerprint),
                    .destination(destination),
                ]
            }
            .toBlocking()
            .single()
    }

    /// https://www.mokacoding.com/blog/xcodebuild-destination-options/
    /// https://www.mokacoding.com/blog/how-to-always-run-latest-simulator-cli/
    fileprivate func destination(target: Target) -> Single<String> {
        var platform: Platform!
        switch target.platform {
        case .iOS: platform = .iOS
        case .watchOS: platform = .watchOS
        case .tvOS: platform = .tvOS
        case .macOS: return .just("platform=OS X,arch=x86_64")
        }

        return simulatorController.devicesAndRuntimes()
            .map { (simulatorsAndRuntimes) -> [SimulatorDevice] in
                simulatorsAndRuntimes
                    .filter { $0.runtime.isAvailable && $0.runtime.name.contains(platform.caseValue) }
                    .map { $0.device }
            }
            .flatMap { (devices) -> Single<String> in
                if let device = devices.first {
                    let destination = "platform=\(platform.caseValue) Simulator,name=\(device.name),OS=latest"
                    return .just(destination)
                } else {
                    return .error(CacheFrameworkBuilderError.deviceNotFound(platform: target.platform.caseValue))
                }
            }
    }

    fileprivate func sdk(target: Target) -> String {
        if target.platform == .macOS {
            return target.platform.xcodeDeviceSDK
        } else {
            return target.platform.xcodeSimulatorSDK!
        }
    }

    fileprivate func xcodebuild(projectTarget: XcodeBuildTarget,
                                scheme: String,
                                target: Target,
                                arguments: [XcodeBuildArgument]) throws
    {
        _ = try xcodeBuildController.build(projectTarget,
                                           scheme: scheme,
                                           clean: false,
                                           arguments: arguments)
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) as .framework...", metadata: .subsection)
            })
            .ignoreElements()
            .toBlocking()
            .last()
    }

    fileprivate func exportFrameworksAndDSYMs(into outputDirectory: AbsolutePath,
                                              target: Target,
                                              builtProductsDirFingerprint: String) throws
    {
        let globPattern = "**/.\(builtProductsDirFingerprint).tuist"
        let derivedDataPath = developerEnvironment.derivedDataDirectory
        guard let directory = FileHandler.shared.glob(derivedDataPath, glob: globPattern).first?.parentDirectory else {
            throw CacheFrameworkBuilderError.builtProductsDirectoryNotFound(targetName: target.name)
        }
        guard let framework = FileHandler.shared.glob(directory, glob: target.productNameWithExtension).first else {
            throw CacheFrameworkBuilderError.frameworkNotFound(name: target.productNameWithExtension, derivedDataPath: derivedDataPath)
        }
        let dsyms = FileHandler.shared.glob(directory, glob: "\(target.productNameWithExtension).dSYM")
        try FileHandler.shared.copy(from: framework, to: outputDirectory.appending(component: framework.basename))
        try dsyms.forEach { dsym in
            try FileHandler.shared.copy(from: dsym, to: outputDirectory.appending(component: dsym.basename))
        }
    }
}
