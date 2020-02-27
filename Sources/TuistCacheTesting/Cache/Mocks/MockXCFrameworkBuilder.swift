import Basic
import Foundation
import RxSwift
import TuistCache
import TuistCore

public final class MockXCFrameworkBuilder: XCFrameworkBuilding {
    var buildProjectArgs: [(projectPath: AbsolutePath, target: Target)] = []
    var buildWorkspaceArgs: [(workspacePath: AbsolutePath, target: Target)] = []
    var buildProjectStub: AbsolutePath?
    var buildWorkspaceStub: AbsolutePath?

    public func build(projectPath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        buildProjectArgs.append((projectPath: projectPath, target: target))
        if let buildProjectStub = buildProjectStub {
            return Observable.just(buildProjectStub)
        } else {
            return Observable.just(AbsolutePath.root)
        }
    }

    public func build(workspacePath: AbsolutePath, target: Target) throws -> Observable<AbsolutePath> {
        buildWorkspaceArgs.append((workspacePath: workspacePath, target: target))
        if let buildWorkspaceStub = buildWorkspaceStub {
            return Observable.just(buildWorkspaceStub)
        } else {
            return Observable.just(AbsolutePath.root)
        }
    }
}
