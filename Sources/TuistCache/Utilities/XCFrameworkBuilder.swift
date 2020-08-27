import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

enum XCFrameworkBuilderError: FatalError {
    case nonFrameworkTarget(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .nonFrameworkTarget: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .nonFrameworkTarget(name):
            return "Can't generate an .xcframework from the target '\(name)' because it's not a framework target"
        }
    }
}

public protocol XCFrameworkBuilding {
    /// Returns an observable build an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - workspacePath: Path to the generated .xcworkspace that contains the given target.
    ///   - target: Target whose .xcframework will be generated.
    ///   - withDevice: Define whether the .xcframework will also contain the target built for devices (it only contains the target built for simulators by default).
    /// - Returns: Path to the compiled .xcframework.
    func build(workspacePath: AbsolutePath, target: Target, withDevice: Bool) throws -> Observable<AbsolutePath>

    /// Returns an observable to build an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the generated .xcodeproj that contains the given target.
    ///   - target: Target whose .xcframework will be generated.
    ///   - withDevice: Define whether the .xcframework will also contain the target built for devices (it only contains the target built for simulators by default).
    /// - Returns: Path to the compiled .xcframework.
    func build(projectPath: AbsolutePath, target: Target, withDevice: Bool) throws -> Observable<AbsolutePath>
}

public final class XCFrameworkBuilder: XCFrameworkBuilding {
    // MARK: - Attributes

    /// Xcode build controller instance to run xcodebuild commands.
    private let xcodeBuildController: XcodeBuildControlling

    // MARK: - Init

    /// Initializes the builder.
    /// - Parameter xcodeBuildController: Xcode build controller instance to run xcodebuild commands.
    public init(xcodeBuildController: XcodeBuildControlling) {
        self.xcodeBuildController = xcodeBuildController
    }

    // MARK: - XCFrameworkBuilding

    public func build(workspacePath: AbsolutePath, target: Target, withDevice: Bool) throws -> Observable<AbsolutePath> {
        try build(.workspace(workspacePath), target: target, withDevice: withDevice)
    }

    public func build(projectPath: AbsolutePath, target: Target, withDevice: Bool) throws -> Observable<AbsolutePath> {
        try build(.project(projectPath), target: target, withDevice: withDevice)
    }

    // MARK: - Fileprivate

    fileprivate func deviceBuild(projectTarget: XcodeBuildTarget,
                                 scheme: String,
                                 target: Target,
                                 deviceArchivePath: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
        xcodeBuildController.archive(projectTarget,
                                     scheme: scheme,
                                     clean: false,
                                     archivePath: deviceArchivePath,
                                     arguments: [
                                         .sdk(target.platform.xcodeDeviceSDK),
                                         .buildSetting("SKIP_INSTALL", "NO"),
                                         .buildSetting("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                     ])
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) for device...", metadata: .subsection)
            })
    }

    fileprivate func simulatorBuild(projectTarget: XcodeBuildTarget,
                                    scheme: String,
                                    target: Target,
                                    simulatorArchivePath: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
        xcodeBuildController.archive(projectTarget,
                                     scheme: scheme,
                                     clean: false,
                                     archivePath: simulatorArchivePath,
                                     arguments: [
                                         .sdk(target.platform.xcodeSimulatorSDK!),
                                         .buildSetting("SKIP_INSTALL", "NO"),
                                         .buildSetting("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                     ])
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) for simulator...", metadata: .subsection)
            })
    }

    // swiftlint:disable:next function_body_length
    fileprivate func build(_ projectTarget: XcodeBuildTarget, target: Target, withDevice: Bool) throws -> Observable<AbsolutePath> {
        guard target.product.isFramework else {
            throw XCFrameworkBuilderError.nonFrameworkTarget(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        return try withTemporaryDirectories { outputDirectory, temporaryPath in
            logger.notice("Building .xcframework for \(target.name)...", metadata: .section)

            // Build for the simulator
            var simulatorArchiveObservable: Observable<SystemEvent<XcodeBuildOutput>>
            var simulatorArchivePath: AbsolutePath?
            if target.platform.hasSimulators {
                simulatorArchivePath = temporaryPath.appending(component: "simulator.xcarchive")
                simulatorArchiveObservable = simulatorBuild(
                    projectTarget: projectTarget,
                    scheme: scheme,
                    target: target,
                    simulatorArchivePath: simulatorArchivePath!
                )
            } else {
                simulatorArchiveObservable = Observable.empty()
            }

            // Build for the device - if required
            let deviceArchivePath = temporaryPath.appending(component: "device.xcarchive")
            var deviceArchiveObservable: Observable<SystemEvent<XcodeBuildOutput>>
            if withDevice {
                deviceArchiveObservable = deviceBuild(
                    projectTarget: projectTarget,
                    scheme: scheme,
                    target: target,
                    deviceArchivePath: deviceArchivePath
                )
            } else {
                deviceArchiveObservable = Observable.empty()
            }

            // Build the xcframework
            var frameworkpaths: [AbsolutePath] = [AbsolutePath]()
            if let simulatorArchivePath = simulatorArchivePath {
                frameworkpaths.append(frameworkPath(fromArchivePath: simulatorArchivePath, productName: target.productName))
            } else if withDevice {
                frameworkpaths.append(frameworkPath(fromArchivePath: deviceArchivePath, productName: target.productName))
            }

            let xcframeworkPath = outputDirectory.appending(component: "\(target.productName).xcframework")
            let xcframeworkObservable = xcodeBuildController.createXCFramework(frameworks: frameworkpaths, output: xcframeworkPath)
                .do(onSubscribed: {
                    logger.notice("Exporting xcframework for \(target.platform.caseValue)", metadata: .subsection)
                })

            return deviceArchiveObservable
                .concat(simulatorArchiveObservable)
                .concat(xcframeworkObservable)
                .ignoreElements()
                .andThen(Observable.just(xcframeworkPath))
                .do(afterCompleted: {
                    try FileHandler.shared.delete(temporaryPath)
                })
        }
    }

    /// Returns the path to the framework inside the archive.
    /// - Parameters:
    ///   - archivePath: Path to the .xcarchive.
    ///   - productName: Product name.
    fileprivate func frameworkPath(fromArchivePath archivePath: AbsolutePath, productName: String) -> AbsolutePath {
        archivePath.appending(RelativePath("Products/Library/Frameworks/\(productName).framework"))
    }
}
