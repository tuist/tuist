import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph
import TuistSupportTesting

public final class MockCacheArtifactBuilder: CacheArtifactBuilding {
    public init() {}

    public var invokedCacheOutputTypeGetter = false
    public var invokedCacheOutputTypeGetterCount = 0
    public var stubbedCacheOutputType: CacheOutputType!

    public var cacheOutputType: CacheOutputType {
        invokedCacheOutputTypeGetter = true
        invokedCacheOutputTypeGetterCount += 1
        return stubbedCacheOutputType
    }

    public var invokedBuildWorkspacePath = false
    public var invokedBuildWorkspacePathCount = 0
    public var invokedBuildWorkspacePathParameters: (workspacePath: AbsolutePath, target: Target, outputDirectory: AbsolutePath)?
    public var invokedBuildWorkspacePathParametersList = [(workspacePath: AbsolutePath, target: Target, outputDirectory: AbsolutePath)]()
    public var stubbedBuildWorkspacePathError: Error?

    public func build(workspacePath: AbsolutePath, target: Target, configuration _: String, into outputDirectory: AbsolutePath) throws {
        invokedBuildWorkspacePath = true
        invokedBuildWorkspacePathCount += 1
        invokedBuildWorkspacePathParameters = (workspacePath, target, outputDirectory)
        invokedBuildWorkspacePathParametersList.append((workspacePath, target, outputDirectory))
        if let error = stubbedBuildWorkspacePathError {
            throw error
        }
    }

    public var invokedBuildProjectPath = false
    public var invokedBuildProjectPathCount = 0
    public var invokedBuildProjectPathParameters: (projectPath: AbsolutePath, target: Target, outputDirectory: AbsolutePath)?
    public var invokedBuildProjectPathParametersList = [(projectPath: AbsolutePath, target: Target, outputDirectory: AbsolutePath)]()
    public var stubbedBuildProjectPathError: Error?

    public func build(projectPath: AbsolutePath, target: Target, configuration _: String, into outputDirectory: AbsolutePath) throws {
        invokedBuildProjectPath = true
        invokedBuildProjectPathCount += 1
        invokedBuildProjectPathParameters = (projectPath, target, outputDirectory)
        invokedBuildProjectPathParametersList.append((projectPath, target, outputDirectory))
        if let error = stubbedBuildProjectPathError {
            throw error
        }
    }
}
