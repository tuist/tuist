import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

enum XCFrameworkBuilderError: FatalError {
    case nonFrameworkTarget(String)
    case platformNotSpecified(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .nonFrameworkTarget: return .abort
        case .platformNotSpecified: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .nonFrameworkTarget(name):
            return "Can't generate an .xcframework from the target '\(name)' because it's not a framework target"
        case let .platformNotSpecified(name):
            return "Can't generate an .xcframework from the target '\(name)' because its platform is not specified"
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
    /// - Returns: Path to the compiled .xcframework.
    func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath>

    /// Returns an observable to build an xcframework for the given target.
    /// The target must have framework as product.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the generated .xcodeproj that contains the given target.
    ///   - target: Target whose .xcframework will be generated.
    /// - Returns: Path to the compiled .xcframework.
    func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath>
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

    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.workspace(workspacePath), target: target)
    }

    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.project(projectPath), target: target)
    }

    // MARK: - Fileprivate

    // swiftlint:disable:next function_body_length
    fileprivate func build(_ projectTarget: XcodeBuildTarget, target: Target) throws -> Observable<AbsolutePath> {
        if target.product != .framework {
            throw XCFrameworkBuilderError.nonFrameworkTarget(target.name)
        }

        guard let xcodeDeviceSDK = target.platform.xcodeDeviceSDK else {
            throw XCFrameworkBuilderError.platformNotSpecified(target.name)
        }
        
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        return try withTemporaryDirectories { outputDirectory, temporaryPath in

            logger.notice("Building .xcframework for \(target.name)...", metadata: .section)

            // Build for the device
            // Without the BUILD_LIBRARY_FOR_DISTRIBUTION argument xcodebuild doesn't generate the .swiftinterface file
            let deviceArchivePath = temporaryPath.appending(component: "device.xcarchive")
            let deviceArchiveObservable = xcodeBuildController.archive(projectTarget,
                                                                       scheme: scheme,
                                                                       clean: true,
                                                                       archivePath: deviceArchivePath,
                                                                       arguments: [
                                                                           .sdk(xcodeDeviceSDK),
                                                                           .derivedDataPath(temporaryPath),
                                                                           .buildSetting("SKIP_INSTALL", "NO"),
                                                                           .buildSetting("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                                                       ])
                .printFormattedOutput()
                .do(onSubscribed: {
                    logger.notice("Building \(target.name) for device...", metadata: .subsection)
                })

            // Build for the simulator
            var simulatorArchiveObservable: Observable<SystemEvent<XcodeBuildOutput>>?
            var simulatorArchivePath: AbsolutePath?
            if target.platform.hasSimulators {
                simulatorArchivePath = temporaryPath.appending(component: "simulator.xcarchive")
                simulatorArchiveObservable = xcodeBuildController.archive(projectTarget,
                                                                          scheme: scheme,
                                                                          clean: false,
                                                                          archivePath: simulatorArchivePath!,
                                                                          arguments: [
                                                                              .sdk(target.platform.xcodeSimulatorSDK!),
                                                                              .derivedDataPath(temporaryPath),
                                                                              .buildSetting("SKIP_INSTALL", "NO"),
                                                                              .buildSetting("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES"),
                                                                          ])
                    .printFormattedOutput()
                    .do(onSubscribed: {
                        logger.notice("Building \(target.name) for simulator", metadata: .subsection)
                    })
            }

            // Build the xcframework
            var frameworkpaths = [frameworkPath(fromArchivePath: deviceArchivePath, productName: target.productName)]
            if let simulatorArchivePath = simulatorArchivePath {
                frameworkpaths.append(frameworkPath(fromArchivePath: simulatorArchivePath, productName: target.productName))
            }
            let xcframeworkPath = outputDirectory.appending(component: "\(target.productName).xcframework")
            let xcframeworkObservable = xcodeBuildController.createXCFramework(frameworks: frameworkpaths, output: xcframeworkPath)
                .do(onSubscribed: {
                    logger.notice("Exporting xcframework for \(target.platform.caseValue)", metadata: .subsection)
                })

            return deviceArchiveObservable
                .concat(simulatorArchiveObservable ?? Observable.empty())
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
