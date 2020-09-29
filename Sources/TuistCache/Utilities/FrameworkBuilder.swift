import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public final class FrameworkBuilder: ArtifactBuilding {
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
    public var artifactType: ArtifactType = .framework

    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.workspace(workspacePath), target: target)
    }

    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        try build(.project(projectPath), target: target)
    }

    // MARK: - Fileprivate

    fileprivate func simulatorBuild(projectTarget: XcodeBuildTarget,
                                    scheme: String,
                                    target: Target,
                                    simulatorArchivePath: AbsolutePath) -> Observable<SystemEvent<XcodeBuildOutput>>
    {
        xcodeBuildController.archive(projectTarget,
                                     scheme: scheme,
                                     clean: false,
                                     archivePath: simulatorArchivePath,
                                     arguments: [
                                         .sdk(target.platform.xcodeSimulatorSDK!),
                                     ])
            .printFormattedOutput()
            .do(onSubscribed: {
                logger.notice("Building \(target.name) as .framework for simulator...", metadata: .subsection)
            })
    }

    fileprivate func build(_ projectTarget: XcodeBuildTarget, target: Target) throws -> Observable<AbsolutePath> {
        guard target.product.isFramework else {
            throw BinaryBuilderError.nonFrameworkTargetForFramework(target.name)
        }
        let scheme = target.name.spm_shellEscaped()

        // Create temporary directories
        return try withTemporaryDirectories { _, temporaryPath in
            logger.notice("Building .framework for \(target.name)...", metadata: .section)

            // Build for the simulator
            var simulatorArchiveObservable: Observable<SystemEvent<XcodeBuildOutput>>
            var simulatorArchivePath: AbsolutePath?
            if target.platform.hasSimulators {
                simulatorArchivePath = temporaryPath.appending(component: "\(target.name).xcarchive")
                simulatorArchiveObservable = simulatorBuild(
                    projectTarget: projectTarget,
                    scheme: scheme,
                    target: target,
                    simulatorArchivePath: simulatorArchivePath!
                )
            } else {
                simulatorArchiveObservable = Observable.empty()
            }

            return simulatorArchiveObservable
                .filter { event -> Bool in
                    print("event: \(event)")
                    print("path: \(simulatorArchivePath!)")
                    return true
                }
                .ignoreElements()
                .andThen(Observable.just(self.frameworkPath(fromArchivePath: simulatorArchivePath!,
                                                            productName: target.productName)))
                .do(afterCompleted: {
//                    try FileHandler.shared.delete(temporaryPath)
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
