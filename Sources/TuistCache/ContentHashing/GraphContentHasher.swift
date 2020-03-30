import Checksum
import Foundation
import TuistCore
import TuistSupport
import Basic

public protocol GraphContentHashing {
    func contentHashes(for graph: Graphing) throws -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    private let contentHasher: ContentHashing
    private let coreDataModelsContentHasher: CoreDataModelsContentHashing
    private let sourceFilesContentHasher: SourceFilesContentHashing

    // MARK: - Init

    public init(
        contentHasher: ContentHashing = ContentHasher(),
        sourceFilesContentHasher: SourceFilesContentHashing = SourceFilesContentHasher(),
        coreDataModelsContentHasher: CoreDataModelsContentHashing = CoreDataModelsContentHasher()
    ) {
        self.contentHasher = contentHasher
        self.sourceFilesContentHasher = sourceFilesContentHasher
        self.coreDataModelsContentHasher = coreDataModelsContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(for graph: Graph) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]

        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
        targets.compactMap { target in
            if self.isCacheable(target, visited: &visitedNodes) { return target }
                return nil
            }
        }
        let hashes = try hashableTargets.map { try makeContentHash(of: $0) }
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
        let targetActionsHash = try hash(targetActions: target.actions)
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
            try contentHasher.hash(path)
        }
        return try contentHasher.hash(hashes)
    }

    private func hash(resources: [FileElement]) throws -> String {
        let paths = resources.map { $0.path }
        let hashes = try paths.map { try contentHasher.hash($0) }
        return try contentHasher.hash(hashes)
    }

    private func hash(targetActions: [TargetAction]) throws -> String {
        var stringsToHash: [String] = []
        for targetAction in targetActions {
            var contentHash = ""
            if let path = targetAction.path {
                contentHash = try contentHasher.hash(path)
            }
            let inputPaths = targetAction.inputPaths.map { $0.pathString }
            let outputPaths = targetAction.outputPaths.map { $0.pathString }
            let outputFileListPaths = targetAction.outputFileListPaths.map { $0.pathString }
            let targetStringsToHash = [
                contentHash,
                targetAction.name,
                targetAction.tool ?? "",
                String(targetAction.order.hashValue),
            ] + targetAction.arguments + inputPaths + outputPaths + outputFileListPaths
            stringsToHash.append(try contentHasher.hash(targetStringsToHash))
        }
        return try contentHasher.hash(stringsToHash)
    }
}
