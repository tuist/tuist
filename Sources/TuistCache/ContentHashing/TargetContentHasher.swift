import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol TargetContentHashing {
    func contentHash(for target: TargetNode) throws -> String
}

/// `TargetContentHasher`
/// is responsible for computing a unique hash that identifies a target
public final class TargetContentHasher: TargetContentHashing {
    private let contentHasher: ContentHashing
    private let coreDataModelsContentHasher: CoreDataModelsContentHashing
    private let sourceFilesContentHasher: SourceFilesContentHashing
    private let targetActionsContentHasher: TargetActionsContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing = CacheContentHasher()) {
        self.init(
            contentHasher: contentHasher,
            sourceFilesContentHasher: SourceFilesContentHasher(contentHasher: contentHasher),
            targetActionsContentHasher: TargetActionsContentHasher(contentHasher: contentHasher),
            coreDataModelsContentHasher: CoreDataModelsContentHasher(contentHasher: contentHasher)
        )
    }

    public init(
        contentHasher: ContentHashing,
        sourceFilesContentHasher: SourceFilesContentHashing,
        targetActionsContentHasher: TargetActionsContentHashing,
        coreDataModelsContentHasher: CoreDataModelsContentHashing
    ) {
        self.contentHasher = contentHasher
        self.sourceFilesContentHasher = sourceFilesContentHasher
        self.coreDataModelsContentHasher = coreDataModelsContentHasher
        self.targetActionsContentHasher = targetActionsContentHasher
    }

    // MARK: - TargetContentHashing

    public func contentHash(for targetNode: TargetNode) throws -> String {
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
        return try contentHasher.hash(stringsToHash)
    }

    private func hash(resources: [FileElement]) throws -> String {
        let hashes = try resources.map { try contentHasher.hash(fileAtPath: $0.path) }
        return try contentHasher.hash(hashes)
    }

    // TODO: hash headers, platforms, version, entitlements, info.plist, target.environment, target.filesGroup, targetNode.settings, targetNode.project, targetNode.dependencies ,targetNode.target.dependencies
}
