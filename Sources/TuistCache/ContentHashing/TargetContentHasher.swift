import Foundation
import TSCBasic
import TuistCore
import TuistSupport

// TODO: test TargetContentHasher

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
    private let resourcesContentHasher: ResourcesContentHashing
    private let headersContentHasher: HeadersContentHashing
    private let deploymentTargetContentHasher: DeploymentTargetContentHashing
    private let infoPlistContentHasher: InfoPlistContentHashing
    private let settingsContentHasher: SettingsContentHashing
    private let dependenciesContentHasher: DependenciesContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing = CacheContentHasher()) {
        self.init(
            contentHasher: contentHasher,
            sourceFilesContentHasher: SourceFilesContentHasher(contentHasher: contentHasher),
            targetActionsContentHasher: TargetActionsContentHasher(contentHasher: contentHasher),
            coreDataModelsContentHasher: CoreDataModelsContentHasher(contentHasher: contentHasher),
            resourcesContentHasher: ResourcesContentHasher(contentHasher: contentHasher),
            headersContentHasher: HeadersContentHasher(contentHasher: contentHasher),
            deploymentTargetContentHasher: DeploymentTargetContentHasher(contentHasher: contentHasher),
            infoPlistContentHasher: InfoPlistContentHasher(contentHasher: contentHasher),
            settingsContentHasher: SettingsContentHasher(contentHasher: contentHasher),
            dependenciesContentHasher: DependenciesContentHasher(contentHasher: contentHasher)
        )
    }

    public init(
        contentHasher: ContentHashing,
        sourceFilesContentHasher: SourceFilesContentHashing,
        targetActionsContentHasher: TargetActionsContentHashing,
        coreDataModelsContentHasher: CoreDataModelsContentHashing,
        resourcesContentHasher: ResourcesContentHashing,
        headersContentHasher: HeadersContentHashing,
        deploymentTargetContentHasher: DeploymentTargetContentHashing,
        infoPlistContentHasher: InfoPlistContentHashing,
        settingsContentHasher: SettingsContentHashing,
        dependenciesContentHasher: DependenciesContentHashing
    ) {
        self.contentHasher = contentHasher
        self.sourceFilesContentHasher = sourceFilesContentHasher
        self.coreDataModelsContentHasher = coreDataModelsContentHasher
        self.targetActionsContentHasher = targetActionsContentHasher
        self.resourcesContentHasher = resourcesContentHasher
        self.headersContentHasher = headersContentHasher
        self.deploymentTargetContentHasher = deploymentTargetContentHasher
        self.infoPlistContentHasher = infoPlistContentHasher
        self.settingsContentHasher = settingsContentHasher
        self.dependenciesContentHasher = dependenciesContentHasher
    }

    // MARK: - TargetContentHashing

    public func contentHash(for targetNode: TargetNode) throws -> String {
        let target = targetNode.target
        let sourcesHash = try sourceFilesContentHasher.hash(sources: target.sources)
        let resourcesHash = try resourcesContentHasher.hash(resources: target.resources)
        let coreDataModelHash = try coreDataModelsContentHasher.hash(coreDataModels: target.coreDataModels)
        let targetActionsHash = try targetActionsContentHasher.hash(targetActions: target.actions)
        let dependenciesHash = try dependenciesContentHasher.hash(dependencies: target.dependencies)
        let environmentHash = try contentHasher.hash(target.environment)

        var stringsToHash = [target.name,
                             target.platform.rawValue,
                             target.product.rawValue,
                             target.bundleId,
                             target.productName,
                             // settings
                             dependenciesHash,
                             sourcesHash,
                             resourcesHash,
                             coreDataModelHash,
                             targetActionsHash,
                             environmentHash]
        if let headers = target.headers {
            let headersHash = try headersContentHasher.hash(headers: headers)
            stringsToHash.append(headersHash)
        }
        if let deploymentTarget = target.deploymentTarget {
            let deploymentTargetHash = try deploymentTargetContentHasher.hash(deploymentTarget: deploymentTarget)
            stringsToHash.append(deploymentTargetHash)
        }
        if let infoPlist = target.infoPlist {
            let infoPlistHash = try infoPlistContentHasher.hash(plist: infoPlist)
            stringsToHash.append(infoPlistHash)
        }
        if let entitlements = target.entitlements {
            let entitlementsHash = try contentHasher.hash(fileAtPath: entitlements)
            stringsToHash.append(entitlementsHash)
        }
        if let settings = target.settings {
            let settingsHash = try settingsContentHasher.hash(settings: settings)
            stringsToHash.append(settingsHash)
        }

        return try contentHasher.hash(stringsToHash)
    }
}
