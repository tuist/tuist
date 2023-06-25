import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

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
    private let deploymentTargetContentHasher: DeploymentTargetContentHashing
    private let infoPlistContentHasher: InfoPlistContentHashing
    private let settingsContentHasher: SettingsContentHashing
    private let dependenciesContentHasher: DependenciesContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        self.init(
            contentHasher: contentHasher,
            sourceFilesContentHasher: SourceFilesContentHasher(contentHasher: contentHasher),
            targetScriptsContentHasher: TargetScriptsContentHasher(contentHasher: contentHasher),
            coreDataModelsContentHasher: CoreDataModelsContentHasher(contentHasher: contentHasher),
            resourcesContentHasher: ResourcesContentHasher(contentHasher: contentHasher),
            copyFilesContentHasher: CopyFilesContentHasher(contentHasher: contentHasher),
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
        targetScriptsContentHasher: TargetScriptsContentHashing,
        coreDataModelsContentHasher: CoreDataModelsContentHashing,
        resourcesContentHasher: ResourcesContentHashing,
        copyFilesContentHasher: CopyFilesContentHashing,
        headersContentHasher: HeadersContentHashing,
        deploymentTargetContentHasher: DeploymentTargetContentHashing,
        infoPlistContentHasher: InfoPlistContentHashing,
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
        self.infoPlistContentHasher = infoPlistContentHasher
        self.settingsContentHasher = settingsContentHasher
        self.dependenciesContentHasher = dependenciesContentHasher
    }

    // MARK: - TargetContentHashing

    // swiftlint:disable:next function_body_length
    public func contentHash(
        for graphTarget: GraphTarget,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String],
        additionalStrings: [String] = []
    ) throws -> String {
        let sourcesHash = try sourceFilesContentHasher.hash(sources: graphTarget.target.sources)
        let resourcesHash = try resourcesContentHasher.hash(resources: graphTarget.target.resources)
        let copyFilesHash = try copyFilesContentHasher.hash(copyFiles: graphTarget.target.copyFiles)
        let coreDataModelHash = try coreDataModelsContentHasher.hash(coreDataModels: graphTarget.target.coreDataModels)
        let targetScriptsHash = try targetScriptsContentHasher.hash(
            targetScripts: graphTarget.target.scripts,
            sourceRootPath: graphTarget.project.sourceRootPath
        )
        let dependenciesHash = try dependenciesContentHasher.hash(
            graphTarget: graphTarget,
            hashedTargets: &hashedTargets,
            hashedPaths: &hashedPaths
        )
        let environmentHash = try contentHasher.hash(graphTarget.target.environment)
        var stringsToHash = [
            graphTarget.target.name,
            graphTarget.target.platform.rawValue,
            graphTarget.target.product.rawValue,
            graphTarget.target.bundleId,
            graphTarget.target.productName,
            dependenciesHash,
            sourcesHash,
            resourcesHash,
            copyFilesHash,
            coreDataModelHash,
            targetScriptsHash,
            environmentHash,
        ]
        if let headers = graphTarget.target.headers {
            let headersHash = try headersContentHasher.hash(headers: headers)
            stringsToHash.append(headersHash)
        }
        if let deploymentTarget = graphTarget.target.deploymentTarget {
            let deploymentTargetHash = try deploymentTargetContentHasher.hash(deploymentTarget: deploymentTarget)
            stringsToHash.append(deploymentTargetHash)
        }
        if let infoPlist = graphTarget.target.infoPlist {
            let infoPlistHash = try infoPlistContentHasher.hash(plist: infoPlist)
            stringsToHash.append(infoPlistHash)
        }
        if let entitlements = graphTarget.target.entitlements {
            let entitlementsHash = try contentHasher.hash(path: entitlements)
            stringsToHash.append(entitlementsHash)
        }
        if let settings = graphTarget.target.settings {
            let settingsHash = try settingsContentHasher.hash(settings: settings)
            stringsToHash.append(settingsHash)
        }
        stringsToHash += additionalStrings
        switch graphTarget.target.deploymentTarget {
        case .macOS, .none:
            stringsToHash.append(DeveloperEnvironment.shared.architecture.rawValue)
        case .iOS, .watchOS, .tvOS, .visionOS:
            break
        }

        return try contentHasher.hash(stringsToHash)
    }
}
