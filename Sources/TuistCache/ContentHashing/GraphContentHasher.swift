import Checksum
import Foundation
import TuistCore
import TuistSupport
import TSCBasic

public protocol GraphContentHashing {
    func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    private let contentHasher: ContentHashing
    private let coreDataModelsContentHasher: CoreDataModelsContentHashing
    private let sourceFilesContentHasher: SourceFilesContentHashing
    private let targetActionsContentHasher: TargetActionsContentHashing

    // MARK: - Init

    public init(
        contentHasher: ContentHashing = CacheContentHasher(),
        sourceFilesContentHasher: SourceFilesContentHashing = SourceFilesContentHasher(),
        targetActionsContentHasher: TargetActionsContentHashing = TargetActionsContentHasher(),
        coreDataModelsContentHasher: CoreDataModelsContentHashing = CoreDataModelsContentHasher()
    ) {
        self.contentHasher = contentHasher
        self.sourceFilesContentHasher = sourceFilesContentHasher
        self.coreDataModelsContentHasher = coreDataModelsContentHasher
        self.targetActionsContentHasher = targetActionsContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
            targets.compactMap { target in
            if self.isCacheable(target, visited: &visitedNodes) { return target }
                return nil
            }
        }
        let hashes = try hashableTargets.map { try hash(targetNode: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }


    // MARK: - Private

    fileprivate func isCacheable(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        let isFramework = target.target.product == .framework
        let noXCTestDependency = target.sdkDependencies.first(where: { $0.name == "XCTest.framework" }) == nil
        let allTargetDependenciesAreHasheable = target.targetDependencies.allSatisfy { isCacheable($0, visited: &visited) }
        let cacheable = isFramework && noXCTestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }

    private func hash(targetNode: TargetNode) throws -> String {
        let target = targetNode.target
        let sourcesHash = try sourceFilesContentHasher.hash(sources: target.sources)
        let resourcesHash = try hash(resources: target.resources)
        let coreDataModelHash = try coreDataModelsContentHasher.hash(coreDataModels: target.coreDataModels)
        let targetActionsHash = try targetActionsContentHasher.hash(targetActions: target.actions)
        let stringsToHash = [sourcesHash,
                             target.name,
                             target.platform.rawValue,
                             target.product.rawValue,
                             target.bundleId,
                             target.productName,
                             resourcesHash,
                             coreDataModelHash,
                             targetActionsHash]
        //TODO: hash headers, platforms, version, entitlements, info.plist, target.environment, target.filesGroup, targetNode.settings, targetNode.project, targetNode.dependencies ,targetNode.target.dependencies

        return try contentHasher.hash(stringsToHash)
    }

    private func hash(headers: Headers) throws -> String {
        let hashes = try (headers.private + headers.project + headers.project).map { path in
            try contentHasher.hash(fileAtPath: path)
        }
        return try contentHasher.hash(hashes)
    }

    private func hash(resources: [FileElement]) throws -> String {
        let paths = resources.map { $0.path }
        let hashes = try paths.map { try contentHasher.hash(fileAtPath: $0) }
        return try contentHasher.hash(hashes)
    }
}
