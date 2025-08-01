import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol TargetContentHashing {
    func contentHash(
        for target: GraphTarget,
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String],
        destination: SimulatorDeviceAndRuntime?,
        additionalStrings: [String]
    ) async throws -> TargetContentHash
}

public struct TargetContentHash {
    public let hash: String
    public let hashedPaths: [AbsolutePath: String]
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
        let xcconfigHasher = XCConfigContentHasher(contentHasher: contentHasher)
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
            settingsContentHasher: SettingsContentHasher(contentHasher: contentHasher, xcconfigHasher: xcconfigHasher),
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
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String],
        destination: SimulatorDeviceAndRuntime?,
        additionalStrings: [String] = []
    ) async throws -> TargetContentHash {
        let projectHash: String? = switch graphTarget.project.type {
        case let .external(hash: hash): hash
        case .local: nil
        }
        let settingsHash: String?
        if let settings = graphTarget.target.settings {
            settingsHash = try await settingsContentHasher.hash(settings: settings)
        } else {
            settingsHash = nil
        }

        let projectSettingsHash = try await settingsContentHasher.hash(settings: graphTarget.project.settings)

        let destinations = graphTarget.target.destinations.map(\.rawValue).sorted()
        let dependenciesHash = try await dependenciesContentHasher.hash(
            graphTarget: graphTarget,
            hashedTargets: hashedTargets,
            hashedPaths: hashedPaths
        )

        if let projectHash {
            return TargetContentHash(
                hash: try contentHasher.hash(
                    [
                        projectHash,
                        graphTarget.target.product.rawValue,
                        projectSettingsHash,
                        settingsHash,
                        dependenciesHash.hash,
                    ].compactMap { $0 } + destinations + additionalStrings
                ),
                hashedPaths: [:]
            )
        }
        var hashedPaths = hashedPaths
        let sourcesHash = try await sourceFilesContentHasher.hash(identifier: "sources", sources: graphTarget.target.sources).hash
        let resourcesHash = try await resourcesContentHasher
            .hash(identifier: "resources", resources: graphTarget.target.resources).hash
        let copyFilesHash = try await copyFilesContentHasher
            .hash(identifier: "copyFiles", copyFiles: graphTarget.target.copyFiles).hash
        let coreDataModelHash = try await coreDataModelsContentHasher.hash(coreDataModels: graphTarget.target.coreDataModels)
        let targetScriptsHash = try await targetScriptsContentHasher.hash(
            targetScripts: graphTarget.target.scripts,
            sourceRootPath: graphTarget.project.sourceRootPath
        )

        hashedPaths = dependenciesHash.hashedPaths
        let environmentHash = try contentHasher.hash(graphTarget.target.environmentVariables.mapValues(\.value))
        let destinationHashes: [String] = if let destination, graphTarget.target.product == .uiTests {
            [
                destination.device.name,
                destination.device.runtimeIdentifier,
            ]
        } else {
            []
        }
        var stringsToHash = [
            graphTarget.target.name,
            graphTarget.target.product.rawValue,
            graphTarget.target.bundleId,
            graphTarget.target.productName,
            dependenciesHash.hash,
            sourcesHash,
            resourcesHash,
            copyFilesHash,
            coreDataModelHash,
            targetScriptsHash,
            environmentHash,
        ] + destinations + additionalStrings + destinationHashes

        stringsToHash.append(contentsOf: graphTarget.target.destinations.map(\.rawValue).sorted())

        if let headers = graphTarget.target.headers {
            let headersHash = try await headersContentHasher.hash(headers: headers)
            stringsToHash.append(headersHash)
        }

        let deploymentTargetHash = try deploymentTargetContentHasher.hash(deploymentTargets: graphTarget.target.deploymentTargets)
        stringsToHash.append(deploymentTargetHash)

        if let infoPlist = graphTarget.target.infoPlist {
            let infoPlistHash = try await plistContentHasher.hash(plist: .infoPlist(infoPlist))
            stringsToHash.append(infoPlistHash)
        }
        if let entitlements = graphTarget.target.entitlements {
            let entitlementsHash = try await plistContentHasher.hash(plist: .entitlements(entitlements))
            stringsToHash.append(entitlementsHash)
        }

        stringsToHash.append(projectSettingsHash)

        if let settingsHash {
            stringsToHash.append(settingsHash)
        }

        return TargetContentHash(
            hash: try contentHasher.hash(stringsToHash),
            hashedPaths: hashedPaths
        )
    }
}
