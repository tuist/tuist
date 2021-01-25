import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
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

    /// a map between the path of a project or workspace, and the path to derived data
    /// using the hash calculated by Xcode.
    private var projectPathHashes: [String: AbsolutePath] = [:]

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

        logger.notice("Building .framework for \(target.name)...", metadata: .section)

        let sdk = self.sdk(target: target)
        let configuration = "Debug" // TODO: Is it available?

        let arguments = try self.arguments(target: target,
                                           sdk: sdk,
                                           configuration: configuration)

        try xcodebuild(
            projectTarget: projectTarget,
            scheme: scheme,
            target: target,
            arguments: arguments
        )

        let buildDirectory = try self.buildDirectory(for: projectTarget,
                                                     target: target,
                                                     configuration: configuration,
                                                     sdk: sdk)

        try exportFrameworksAndDSYMs(from: buildDirectory,
                                     into: outputDirectory,
                                     target: target)
    }

    fileprivate func buildDirectory(for projectTarget: XcodeBuildTarget,
                                    target: Target,
                                    configuration: String,
                                    sdk: String) throws -> AbsolutePath
    {
        let projectPath = projectTarget.path
        let pathString = projectPath.pathString

        if let existing = projectPathHashes[pathString] {
            return existing
        }

        let derivedDataPath = developerEnvironment.derivedDataDirectory
        let hash = try XcodeProjectPathHasher.hashString(for: pathString)
        let buildDirectory = derivedDataPath
            .appending(component: "\(projectTarget.path.basenameWithoutExt)-\(hash)")
            .appending(component: "Build")
            .appending(component: "Products")
            .appending(component: "\(configuration)-\(sdk)")
        projectPathHashes[pathString] = buildDirectory

        return buildDirectory
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
                    .xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
                    .xcarg("GCC_GENERATE_DEBUGGING_SYMBOLS", "YES"),
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

        return simulatorController.findAvailableDevice(platform: platform)
            .flatMap { (deviceAndRuntime) -> Single<String> in
                .just("id=\(deviceAndRuntime.device.udid)")
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

    fileprivate func exportFrameworksAndDSYMs(from buildDirectory: AbsolutePath,
                                              into outputDirectory: AbsolutePath,
                                              target: Target) throws
    {
        logger.info("Exporting built \(target.name) framework and dsym...")

        guard let framework = FileHandler.shared.glob(buildDirectory, glob: target.productNameWithExtension).first else {
            let derivedDataPath = developerEnvironment.derivedDataDirectory
            throw CacheFrameworkBuilderError.frameworkNotFound(name: target.productNameWithExtension, derivedDataPath: derivedDataPath)
        }
        let dsyms = FileHandler.shared.glob(buildDirectory, glob: "\(target.productNameWithExtension).dSYM")
        try FileHandler.shared.copy(from: framework, to: outputDirectory.appending(component: framework.basename))
        try dsyms.forEach { dsym in
            try FileHandler.shared.copy(from: dsym, to: outputDirectory.appending(component: dsym.basename))
        }

        logger.info("Done exporting from \(target.name) into Tuist cache")
    }
}
