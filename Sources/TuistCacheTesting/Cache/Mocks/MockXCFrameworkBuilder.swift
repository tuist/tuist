import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockXCFrameworkBuilder: XCFrameworkBuilding {
    public var buildProjectArgs: [(projectPath: AbsolutePath, target: Target, includeDeviceArch: Bool)] = []
    public var buildWorkspaceArgs: [(workspacePath: AbsolutePath, target: Target, includeDeviceArch: Bool)] = []
    public var buildProjectStub: ((AbsolutePath, Target) -> Result<AbsolutePath, Error>)?
    public var buildWorkspaceStub: ((AbsolutePath, Target) -> Result<AbsolutePath, Error>)?

    public init() {}

    public func build(projectPath: AbsolutePath, target: Target, includeDeviceArch: Bool) throws -> Observable<AbsolutePath> {
        buildProjectArgs.append((projectPath: projectPath, target: target, includeDeviceArch: includeDeviceArch))
        if let buildProjectStub = buildProjectStub {
            switch buildProjectStub(projectPath, target) {
            case let .failure(error):
                return Observable.error(error)
            case let .success(path):
                return Observable.just(path)
            }
        } else {
            return Observable.just(AbsolutePath.root)
        }
    }

    public func build(workspacePath: AbsolutePath, target: Target, includeDeviceArch: Bool) throws -> Observable<AbsolutePath> {
        buildWorkspaceArgs.append((workspacePath: workspacePath, target: target, includeDeviceArch: includeDeviceArch))
        if let buildWorkspaceStub = buildWorkspaceStub {
            switch buildWorkspaceStub(workspacePath, target) {
            case let .failure(error):
                return Observable.error(error)
            case let .success(path):
                return Observable.just(path)
            }
        } else {
            return Observable.just(AbsolutePath.root)
        }
    }
}
