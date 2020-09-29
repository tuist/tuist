import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockFrameworkBuilder: ArtifactBuilding {
    public var buildProjectArgs: [(projectPath: AbsolutePath, target: Target)] = []
    public var buildWorkspaceArgs: [(workspacePath: AbsolutePath, target: Target)] = []
    public var buildProjectStub: ((AbsolutePath, Target) -> Result<AbsolutePath, Error>)?
    public var buildWorkspaceStub: ((AbsolutePath, Target) -> Result<AbsolutePath, Error>)?

    public init() {}

    public var artifactType: ArtifactType = .framework

    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        buildProjectArgs.append((projectPath: projectPath, target: target))
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

    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        buildWorkspaceArgs.append((workspacePath: workspacePath, target: target))
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
