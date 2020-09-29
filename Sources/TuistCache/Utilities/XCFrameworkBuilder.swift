import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public final class XCFrameworkBuilder: ArtifactBuilding {
    
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
    public var artifactType: ArtifactType = .xcframework
    
    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.workspace(workspacePath), target: target)
    }
    
    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.project(projectPath), target: target)
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
    fileprivate func build(_ projectTarget: XcodeBuildTarget, target: Target) throws -> Observable<AbsolutePath> {
        guard target.product.isFramework else {
            throw BinaryBuilderError.nonFrameworkTargetForXCFramework(target.name)
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
            let deviceArchiveObservable = deviceBuild(
                projectTarget: projectTarget,
                scheme: scheme,
                target: target,
                deviceArchivePath: deviceArchivePath
            )
            
            // Build the xcframework
            var frameworkpaths: [AbsolutePath] = [AbsolutePath]()
            if let simulatorArchivePath = simulatorArchivePath {
                frameworkpaths.append(frameworkPath(fromArchivePath: simulatorArchivePath, productName: target.productName))
            }
            frameworkpaths.append(frameworkPath(fromArchivePath: deviceArchivePath, productName: target.productName))
            
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
