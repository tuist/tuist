import Checksum
import Foundation
import TuistCore
import TuistSupport
import Basic

public protocol GraphContentHashing {
    func contentHashes(for graph: Graphing) throws -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func contentHashes(for graph: Graphing) throws -> [TargetNode: String] {
        let hashableTargets = graph.targets.filter { $0.target.product == .framework }
        let hashes = try hashableTargets.map { try hash(targetNode: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    private func hash(targetNode: TargetNode) throws -> String {
        let target = targetNode.target
        let sourcesHash = try hash(sources: target.sources)
        let resourcesHash = try hash(resources: target.resources)
        let coreDataModelHash = try hash(coreDataModels: target.coreDataModels)
        let targetActionsHash = try hash(targetActions: target.actions)
        let environmentHash = String(target.environment.hashValue)
        let filesGroupHash = String(target.filesGroup.hashValue)
        var stringsToHash = [sourcesHash,
                             target.name,
                             target.platform.rawValue,
                             target.product.rawValue,
                             target.bundleId,
                             target.productName,
                             resourcesHash,
                             coreDataModelHash,
                             targetActionsHash,
                             environmentHash,
                             filesGroupHash]
        if let headers = target.headers {
            stringsToHash.append(String(headers.hashValue))
        }
        if let settings = target.settings {
            stringsToHash.append(String(settings.hashValue))
        }
        if let platform = target.deploymentTarget?.platform {
            stringsToHash.append(platform)
        }
        if let version = target.deploymentTarget?.version {
            stringsToHash.append(version)
        }
        if let infoPlistPath = target.infoPlist?.path {
            let infoPlistHash = try hash(filePath: infoPlistPath)
            stringsToHash.append(infoPlistHash)
        }
        if let entitlements = target.entitlements {
            stringsToHash.append(try hash(filePath: entitlements))
        }
        
        //TODO: hash dependencies
        return try hash(strings: stringsToHash)
    }

    private func hash(sources: [Target.SourceFile]) throws -> String {
        let sortedSources = sources.sorted(by: { $0.path < $1.path })
        var stringsToHash: [String] = []
        for source in sortedSources {
            let contentHash = try hash(filePath: source.path)
            var sourceHash = contentHash
            if let compilerFlags = source.compilerFlags {
                sourceHash += String(compilerFlags.hashValue)
            }
            stringsToHash.append(sourceHash)
        }
        return try hash(strings: stringsToHash)
    }
    
    private func hash(resources: [FileElement]) throws -> String {
        let paths = resources.map { $0.path }
        let hashes = try paths.map { try hash(filePath: $0) }
        return try hash(strings: hashes)
    }
    
    private func hash(coreDataModels: [CoreDataModel]) throws -> String {
        var stringsToHash: [String] = []
        for cdModel in coreDataModels {
            let contentHash = try hash(filePath: cdModel.path)
            let currentVersionHash = String(cdModel.currentVersion.hashValue)
            let cdModelHash = try hash(strings: [contentHash, currentVersionHash])
            stringsToHash.append(cdModelHash)
        }
        return try hash(strings: stringsToHash)
    }
    
    private func hash(targetActions: [TargetAction]) throws -> String {
        var stringsToHash: [String] = []
        for targetAction in targetActions {
            var contentHash = ""
            if let path = targetAction.path {
                contentHash = try hash(filePath: path)
            }
            let inputPaths = targetAction.inputPaths.map { $0.pathString }
            let outputPaths = targetAction.outputPaths.map { $0.pathString }
            let outputFileListPaths = targetAction.outputFileListPaths.map { $0.pathString }
            let targetActionHash = try hash(strings: [
                contentHash,
                targetAction.name,
                targetAction.tool ?? "",
                String(targetAction.order.hashValue),
                ] + targetAction.arguments + inputPaths + outputPaths + outputFileListPaths)
            stringsToHash.append(targetActionHash)
        }
        return try hash(strings: stringsToHash)
    }
    
    private func hash(strings: [String]) throws -> String {
        guard let joinedHash = strings.joined().checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(strings.joined())
        }
        return joinedHash
    }

    private func hash(filePath: AbsolutePath) throws -> String {
        guard let sourceData = try? fileHandler.readFile(filePath) else {
            throw ContentHashingError.fileNotFound(filePath)
        }
        guard let hash = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(filePath)
        }
        return hash
    }
}
