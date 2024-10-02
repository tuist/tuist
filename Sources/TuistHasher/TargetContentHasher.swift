import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

public protocol TargetContentHashing {
    func contentHash(
        for target: GraphTarget,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String],
        additionalStrings: [String]
    ) throws -> String
}

/// `TargetContentHasher`
/// is responsible for computing a unique hash that identifies a target
public final class TargetContentHasher: TargetContentHashing {
    private let contentHasher: ContentHashing
    private let coreDataModelsContentHasher: CoreDataModelsContentHashing
    private let sourceFilesContentHasher: SourceFilesContentHashing
    private let targetScriptsContentHasher: TargetScriptsContentHashing
    private let resourcesContentHasher: ResourcesContentHashing
    private let copyFilesContentHasher: CopyFilesContentHashing
    private let headersContentHasher: HeadersContentHashing
    private let deploymentTargetContentHasher: DeploymentTargetsContentHashing
    private let plistContentHasher: PlistContentHashing
    private let settingsContentHasher: SettingsContentHashing
    private let dependenciesContentHasher: DependenciesContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        let platformConditionContentHasher = PlatformConditionContentHasher(contentHasher: contentHasher)
        self.init(
            contentHasher: contentHasher,
            sourceFilesContentHasher: SourceFilesContentHasher(
                contentHasher: contentHasher,
                platformConditionContentHasher: platformConditionContentHasher
            ),
            targetScriptsContentHasher: TargetScriptsContentHasher(contentHasher: contentHasher),
            coreDataModelsContentHasher: CoreDataModelsContentHasher(contentHasher: contentHasher),
            resourcesContentHasher: ResourcesContentHasher(contentHasher: contentHasher),
            copyFilesContentHasher: CopyFilesContentHasher(
                contentHasher: contentHasher,
                platformConditionContentHasher: platformConditionContentHasher
            ),
            headersContentHasher: HeadersContentHasher(contentHasher: contentHasher),
            deploymentTargetContentHasher: DeploymentTargetsContentHasher(contentHasher: contentHasher),
            plistContentHasher: PlistContentHasher(contentHasher: contentHasher),
            settingsContentHasher: SettingsContentHasher(contentHasher: contentHasher),
            dependenciesContentHasher: DependenciesContentHasher(contentHasher: contentHasher)
        )
    }

    public init(
        contentHasher: ContentHashing,
        sourceFilesContentHasher: SourceFilesContentHashing,
        targetScriptsContentHasher: TargetScriptsContentHashing,
        coreDataModelsContentHasher: CoreDataModelsContentHashing,
        resourcesContentHasher: ResourcesContentHashing,
        copyFilesContentHasher: CopyFilesContentHashing,
        headersContentHasher: HeadersContentHashing,
        deploymentTargetContentHasher: DeploymentTargetsContentHashing,
        plistContentHasher: PlistContentHashing,
        settingsContentHasher: SettingsContentHashing,
        dependenciesContentHasher: DependenciesContentHashing
    ) {
        self.contentHasher = contentHasher
        self.sourceFilesContentHasher = sourceFilesContentHasher
        self.coreDataModelsContentHasher = coreDataModelsContentHasher
        self.targetScriptsContentHasher = targetScriptsContentHasher
        self.resourcesContentHasher = resourcesContentHasher
        self.copyFilesContentHasher = copyFilesContentHasher
        self.headersContentHasher = headersContentHasher
        self.deploymentTargetContentHasher = deploymentTargetContentHasher
        self.plistContentHasher = plistContentHasher
        self.settingsContentHasher = settingsContentHasher
        self.dependenciesContentHasher = dependenciesContentHasher
    }

    // MARK: - TargetContentHashing

    public func contentHash(
        for graphTarget: GraphTarget,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String],
        additionalStrings: [String] = []
    ) throws -> String {
        let sourceRootPath = graphTarget.project.sourceRootPath
        let sourcesHash = try sourceFilesContentHasher.hash(
            identifier: "sources",
            sources: graphTarget.target.sources,
            sourceRootPath: sourceRootPath
        ).hash

        let resourcesHash = try resourcesContentHasher.hash(
            identifier: "resources",
            resources: graphTarget.target.resources,
            sourceRootPath: sourceRootPath
        ).hash
        let copyFilesHash = try copyFilesContentHasher.hash(
            identifier: "copyFiles",
            copyFiles: graphTarget.target.copyFiles,
            sourceRootPath: sourceRootPath
        ).hash
        let coreDataModelHash = try coreDataModelsContentHasher.hash(
            identifier: "coreDataModels",
            coreDataModels: graphTarget.target.coreDataModels,
            sourceRootPath: sourceRootPath
        ).hash
        let scriptsHash = try targetScriptsContentHasher.hash(
            identifier: "scripts",
            targetScripts: graphTarget.target.scripts,
            sourceRootPath: sourceRootPath
        ).hash

        // NEXT

        let dependenciesHash = try dependenciesContentHasher.hash(
            graphTarget: graphTarget,
            hashedTargets: &hashedTargets,
            hashedPaths: &hashedPaths
        )
        let environmentHash = try contentHasher.hash(graphTarget.target.environmentVariables.mapValues(\.value))
        var stringsToHash = [
            graphTarget.target.name,
            graphTarget.target.product.rawValue,
            graphTarget.target.bundleId,
            graphTarget.target.productName,
            dependenciesHash,
            sourcesHash,
            resourcesHash,
            copyFilesHash,
            coreDataModelHash,
            scriptsHash,
            environmentHash,
        ]

        stringsToHash.append(contentsOf: graphTarget.target.destinations.map(\.rawValue).sorted())

        if let headers = graphTarget.target.headers {
            let headersHash = try headersContentHasher.hash(headers: headers)
            stringsToHash.append(headersHash)
        }

        let deploymentTargetHash = try deploymentTargetContentHasher.hash(deploymentTargets: graphTarget.target.deploymentTargets)
        stringsToHash.append(deploymentTargetHash)

        if let infoPlist = graphTarget.target.infoPlist {
            let infoPlistHash = try plistContentHasher.hash(plist: .infoPlist(infoPlist))
            stringsToHash.append(infoPlistHash)
        }
        if let entitlements = graphTarget.target.entitlements {
            let entitlementsHash = try plistContentHasher.hash(plist: .entitlements(entitlements))
            stringsToHash.append(entitlementsHash)
        }
        if let settings = graphTarget.target.settings {
            let settingsHash = try settingsContentHasher.hash(settings: settings)
            stringsToHash.append(settingsHash)
        }
        stringsToHash += additionalStrings

        return try contentHasher.hash(stringsToHash)
    }
}
