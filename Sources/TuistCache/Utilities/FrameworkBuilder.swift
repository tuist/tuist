import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public enum FrameworkBuilderError: FatalError {
    case frameworkNotFound(name: String, derivedDataPath: AbsolutePath)
    case deviceNotFound(platform: String)

    public var description: String {
        switch self {
        case let .frameworkNotFound(name, derivedDataPath):
            return "Couldn't find framework '\(name)' in the derived data directory: \(derivedDataPath.pathString)"
        case let .deviceNotFound(platform):
            return "Couldn't find an available device for platform: '\(platform)'"
        }
    }

    public var type: ErrorType {
        switch self {
        case .frameworkNotFound: return .bug
        case .deviceNotFound: return .bug
        }
    }
}

public final class FrameworkBuilder: ArtifactBuilding {
    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    /// Simulator controller.
    private let simulatorController: SimulatorControlling

    // MARK: - Init

    /// Initializes the builder.
    /// - Parameter xcodeBuildController: Xcode build controller instance to run xcodebuild commands.
    public init(xcodeBuildController: XcodeBuildControlling,
                simulatorController: SimulatorControlling = SimulatorController())
    {
        self.xcodeBuildController = xcodeBuildController
        self.simulatorController = simulatorController
    }

    // MARK: - ArtifactBuilding

    /// Returns the type of artifact that the concrete builder processes
    public var cacheOutputType: CacheOutputType = .framework

    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<[AbsolutePath]> {
        try build(.workspace(workspacePath), target: target)
    }

    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<[AbsolutePath]> {
        try build(.project(projectPath), target: target)
    }

    // MARK: - Fileprivate

    fileprivate func build(_ projectTarget: XcodeBuildTarget, target: Target) throws -> Observable<[AbsolutePath]> {
        guard target.product.isFramework else {
            throw BinaryBuilderError.nonFrameworkTargetForFramework(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        return try FileHandler.shared.inTemporaryDirectory(removeOnCompletion: false) { _ in
            logger.notice("Building .framework for \(target.name)...", metadata: .section)

            let sdk = self.sdk(target: target)
            let configuration = "Debug" // TODO: Is it available?

            let argumentsObservable = self.arguments(target: target, sdk: sdk, configuration: configuration).asObservable()

            return argumentsObservable.flatMap { (arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>> in
                self.xcodebuild(
                    projectTarget: projectTarget,
                    scheme: scheme,
                    target: target,
                    arguments: arguments
                )
            }
            .ignoreElements()
            .andThen(derivedDataFramework(target: target, configuration: configuration, sdk: sdk))
            .map { (path: AbsolutePath) -> [AbsolutePath] in [path] }
            .asObservable()
        }
    }

    fileprivate func arguments(target: Target, sdk: String, configuration: String) -> Single<[XcodeBuildArgument]> {
        destination(target: target)
            .map { (destination: String) -> [XcodeBuildArgument] in
                [
                    .derivedDataPath(Environment.shared.derivedDataDirectory),
                    .sdk(sdk),
                    .configuration(configuration),
                    .buildSetting("ONLY_ACTIVE_ARCH", "YES"),
                    .destination(destination),
                ]
            }
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
                    return .error(FrameworkBuilderError.deviceNotFound(platform: target.platform.caseValue))
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

    fileprivate func derivedDataFramework(target: Target, configuration: String, sdk: String) -> Single<AbsolutePath> {
        Single.create { (observer) -> Disposable in
            let derivedDataPath = Environment.shared.derivedDataDirectory
            let frameworkName = "\(target.productName).framework"
            let glob: String
            if target.platform == .macOS {
                glob = "Build/Products/\(configuration)/\(frameworkName)"
            } else {
                glob = "Build/Products/\(configuration)-\(sdk)/\(frameworkName)"
            }
            if let frameworkPath = FileHandler.shared.glob(derivedDataPath, glob: glob).first {
                observer(.success(frameworkPath))
            } else {
                observer(.error(FrameworkBuilderError.frameworkNotFound(name: frameworkName, derivedDataPath: derivedDataPath)))
            }
            return Disposables.create {}
        }
    }

    fileprivate func xcodebuild(projectTarget: XcodeBuildTarget,
                                scheme: String,
                                target: Target,
                                arguments: [XcodeBuildArgument]) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        xcodeBuildController.build(projectTarget,
                                   scheme: scheme,
                                   clean: false,
                                   arguments: arguments)
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) as .framework...", metadata: .subsection)
            })
    }
}
