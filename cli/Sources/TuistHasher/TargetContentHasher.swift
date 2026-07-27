import Foundation
import Mockable
import Path
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

@Mockable
public protocol TargetContentHashing {
    func contentHash(
        for target: GraphTarget,
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String],
        destination: SimulatorDeviceAndRuntime?,
        embeddedProductReferences: [String],
        additionalStrings: [String]
    ) async throws -> TargetContentHash
}

public struct TargetContentHash: Equatable {
    public let hash: String
    public let hashedPaths: [AbsolutePath: String]
    public let subhashes: TargetContentHashSubhashes

    #if DEBUG
        public static func test(
            hash: String = "test-hash",
            hashedPaths: [AbsolutePath: String] = [:],
            subhashes: TargetContentHashSubhashes = .test()
        ) -> TargetContentHash {
            TargetContentHash(
                hash: hash,
                hashedPaths: hashedPaths,
                subhashes: subhashes
            )
        }
    #endif
}

/// `TargetContentHasher`
/// is responsible for computing a unique hash that identifies a target
public struct TargetContentHasher: TargetContentHashing {
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
    private let foreignBuildHasher: ForeignBuildHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        let platformConditionContentHasher = PlatformConditionContentHasher(
            contentHasher: contentHasher
        )
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
            deploymentTargetContentHasher: DeploymentTargetsContentHasher(
                contentHasher: contentHasher
            ),
            plistContentHasher: PlistContentHasher(contentHasher: contentHasher),
            settingsContentHasher: SettingsContentHasher(
                contentHasher: contentHasher, xcconfigHasher: xcconfigHasher
            ),
            dependenciesContentHasher: DependenciesContentHasher(contentHasher: contentHasher),
            foreignBuildHasher: ForeignBuildHasher(contentHasher: contentHasher)
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
        dependenciesContentHasher: DependenciesContentHashing,
        foreignBuildHasher: ForeignBuildHashing
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
        self.foreignBuildHasher = foreignBuildHasher
    }

    // MARK: - TargetContentHashing

    // swiftlint:disable:next function_body_length
    public func contentHash(
        for graphTarget: GraphTarget,
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String],
        destination: SimulatorDeviceAndRuntime?,
        embeddedProductReferences: [String] = [],
        additionalStrings: [String] = []
    ) async throws -> TargetContentHash {
        let embeddedProductReferencesHash: String? = embeddedProductReferences.isEmpty
            ? nil
            : try contentHasher.hash(embeddedProductReferences.sorted())
        let projectHash: String? =
            switch graphTarget.project.type {
            case let .external(hash: hash): hash
            case .local: nil
            }
        let settingsHash: String?
        if let settings = graphTarget.target.settings {
            settingsHash = try await settingsContentHasher.hash(settings: settings)
        } else {
            settingsHash = nil
        }

        let projectSettingsHash = try await settingsContentHasher.hash(
            settings: graphTarget.project.settings
        )

        let destinations = graphTarget.target.destinations.map(\.rawValue).sorted()
        let dependenciesHash = try await dependenciesContentHasher.hash(
            graphTarget: graphTarget,
            hashedTargets: hashedTargets,
            hashedPaths: hashedPaths
        )

        if let projectHash {
            let hash = try contentHasher.hash(
                [
                    projectHash,
                    graphTarget.target.name,
                    graphTarget.target.product.rawValue,
                    projectSettingsHash,
                    settingsHash,
                    dependenciesHash.hash,
                    embeddedProductReferencesHash,
                ].compactMap { $0 } + destinations + additionalStrings
            )

            Logger.current.debug("""
            Target content hash for \(graphTarget.target.name) (external project): \(hash)
              Components:
                project: \(projectHash)
                name: \(graphTarget.target.name)
                product: \(graphTarget.target.product.rawValue)
                projectSettings: \(projectSettingsHash)
                targetSettings: \(settingsHash ?? "nil")
                dependencies: \(dependenciesHash.hash)
                embeddedProductReferences: \(embeddedProductReferencesHash ?? "nil")
                destinations: \(destinations.joined(separator: ", "))
                additionalStrings: \(additionalStrings.joined(separator: ", "))
            """)

            let subhashes = TargetContentHashSubhashes(
                dependencies: dependenciesHash.hash,
                projectSettings: projectSettingsHash,
                targetSettings: settingsHash,
                additionalStrings: additionalStrings,
                external: projectHash,
                embeddedProductReferences: embeddedProductReferencesHash
            )

            return TargetContentHash(
                hash: hash,
                hashedPaths: [:],
                subhashes: subhashes
            )
        }
        var hashedPaths = hashedPaths
        let sourcesHash = try await sourceFilesContentHasher.hash(
            identifier: "sources", sources: graphTarget.target.sources
        ).hash
        let resourcesHash =
            try await resourcesContentHasher
                .hash(identifier: "resources", resources: graphTarget.target.resources).hash
        let copyFilesHash =
            try await copyFilesContentHasher
                .hash(identifier: "copyFiles", copyFiles: graphTarget.target.copyFiles).hash
        let coreDataModelHash = try await coreDataModelsContentHasher.hash(
            coreDataModels: graphTarget.target.coreDataModels
        )
        let targetScriptsHash = try await targetScriptsContentHasher.hash(
            targetScripts: graphTarget.target.scripts,
            sourceRootPath: graphTarget.project.sourceRootPath
        )

        hashedPaths = dependenciesHash.hashedPaths
        let environmentHash = try contentHasher.hash(
            graphTarget.target.environmentVariables.mapValues(\.value)
        )
        let destinationHashes: [String] =
            if let destination, graphTarget.target.product == .uiTests {
                [
                    destination.device.name,
                    destination.device.runtimeIdentifier,
                ]
            } else {
                []
            }

        let hashingFilesFilter = HashingFilesFilter()
        let buildableFolderHashes = try await graphTarget.target
            .buildableFolders.sorted(by: { $0.path < $1.path })
            .map { buildableFolder in
                let resolvedFiles = buildableFolder.resolvedFiles
                    .filter { hashingFilesFilter($0.path) }
                    .sorted(by: { $0.path < $1.path })

                return (buildableFolder, resolvedFiles)
            }
            .concurrentFlatMap {
                (buildableFolder: BuildableFolder, buildableFiles: [BuildableFolderFile]) in
                let publicHeaders = Set(buildableFolder.exceptions.flatMap(\.publicHeaders))
                let privateHeaders = Set(buildableFolder.exceptions.flatMap(\.privateHeaders))

                return try await buildableFiles.concurrentMap { buildableFile in
                    let fileHash = try await contentHasher.hash(path: buildableFile.path)
                    let compilerFlagsHash = try contentHasher.hash(
                        buildableFile.compilerFlags ?? ""
                    )
                    var stringsToHash = [fileHash, compilerFlagsHash]

                    if publicHeaders.contains(buildableFile.path) {
                        stringsToHash.append("public-header")
                    }
                    if privateHeaders.contains(buildableFile.path) {
                        stringsToHash.append("private-header")
                    }

                    return try contentHasher.hash(stringsToHash)
                }.sorted()
            }

        // Files contributed to this target from sibling targets' buildable folders via additive cross-target
        // membership (`.exception(target:included:)`). Without folding these in, adding/removing such a membership —
        // or changing an included file's content or compiler flags — would not change this target's hash, so stale
        // cache artifacts could be reused.
        let targetName = graphTarget.target.name
        let foreignBuildableFolderHashes: [String] = try await graphTarget.project.targets.values
            .filter { $0.name != targetName }
            .sorted(by: { $0.name < $1.name })
            .concurrentFlatMap { (otherTarget: Target) -> [String] in
                try await otherTarget.buildableFolders
                    .sorted(by: { $0.path < $1.path })
                    .concurrentFlatMap { (folder: BuildableFolder) -> [String] in
                        let inclusions = folder.exceptions
                            .filter { $0.target == targetName }
                            .flatMap { exception in exception.included.map { (path: $0, exception: exception) } }
                            .filter { hashingFilesFilter($0.path) }
                            .sorted(by: { $0.path < $1.path })
                        return try await inclusions.concurrentMap { inclusion in
                            let fileHash = try await contentHasher.hash(path: inclusion.path)
                            let compilerFlagsHash = try contentHasher.hash(
                                inclusion.exception.compilerFlags[inclusion.path] ?? ""
                            )
                            var inclusionStrings = [
                                otherTarget.name,
                                inclusion.path.relative(to: folder.path).pathString,
                                fileHash,
                                compilerFlagsHash,
                            ]
                            if let condition = inclusion.exception.platformFilters[inclusion.path] {
                                inclusionStrings.append(
                                    contentsOf: condition.platformFilters.map(\.xcodeprojValue).sorted()
                                )
                            }
                            return try contentHasher.hash(inclusionStrings)
                        }
                    }
            }
            .sorted()

        let combinedBuildableFolderHashes = buildableFolderHashes + foreignBuildableFolderHashes
        let buildableFoldersHash: String? = combinedBuildableFolderHashes.isEmpty
            ? nil
            : try contentHasher.hash(combinedBuildableFolderHashes)

        var stringsToHash =
            [
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

        if let buildableFoldersHash {
            stringsToHash.append(buildableFoldersHash)
        }

        stringsToHash.append(contentsOf: graphTarget.target.destinations.map(\.rawValue).sorted())

        let headersHash: String?
        if let headers = graphTarget.target.headers {
            headersHash = try await headersContentHasher.hash(headers: headers)
            stringsToHash.append(headersHash!)
        } else {
            headersHash = nil
        }

        let deploymentTargetHash = try deploymentTargetContentHasher.hash(
            deploymentTargets: graphTarget.target.deploymentTargets
        )
        stringsToHash.append(deploymentTargetHash)

        let infoPlistHash: String?
        if let infoPlist = graphTarget.target.infoPlist {
            infoPlistHash = try await plistContentHasher.hash(plist: .infoPlist(infoPlist))
            stringsToHash.append(infoPlistHash!)
        } else {
            infoPlistHash = nil
        }

        let entitlementsHash: String?
        if let entitlements = graphTarget.target.entitlements {
            entitlementsHash = try await plistContentHasher.hash(
                plist: .entitlements(entitlements)
            )
            stringsToHash.append(entitlementsHash!)
        } else {
            entitlementsHash = nil
        }

        stringsToHash.append(projectSettingsHash)

        if let settingsHash {
            stringsToHash.append(settingsHash)
        }

        if let foreignBuild = graphTarget.target.foreignBuild {
            let inputsResult = try await foreignBuildHasher.hash(
                inputs: foreignBuild.inputs,
                hashedPaths: hashedPaths
            )
            hashedPaths.merge(inputsResult.hashedPaths, uniquingKeysWith: { _, newValue in newValue })
            let foreignBuildHash = try contentHasher.hash(
                "foreignBuild-\(graphTarget.target.name)-\(foreignBuild.script)-\(inputsResult.hash)"
            )
            stringsToHash.append(foreignBuildHash)
        }

        if let embeddedProductReferencesHash {
            stringsToHash.append(embeddedProductReferencesHash)
        }

        let hash = try contentHasher.hash(stringsToHash)

        Logger.current.debug("""
        Target content hash for \(graphTarget.target.name): \(hash)
          Individual sub-hashes:
            name: \(graphTarget.target.name)
            product: \(graphTarget.target.product.rawValue)
            bundleId: \(graphTarget.target.bundleId)
            productName: \(graphTarget.target.productName)
            projectSettings: \(projectSettingsHash)
            targetSettings: \(settingsHash ?? "nil")
            dependencies: \(dependenciesHash.hash)
            sources: \(sourcesHash)
            resources: \(resourcesHash)
            copyFiles: \(copyFilesHash)
            coreDataModels: \(coreDataModelHash)
            targetScripts: \(targetScriptsHash)
            environment: \(environmentHash)
            destinations: \(destinations.joined(separator: ", "))
            destinationHashes: \(destinationHashes.joined(separator: ", "))
            additionalStrings: \(additionalStrings.joined(separator: ", "))
            buildableFolders: \(buildableFoldersHash ?? "nil")
            headers: \(headersHash ?? "nil")
            deploymentTarget: \(deploymentTargetHash)
            infoPlist: \(infoPlistHash ?? "nil")
            entitlements: \(entitlementsHash ?? "nil")
            embeddedProductReferences: \(embeddedProductReferencesHash ?? "nil")
        """)

        let subhashes = TargetContentHashSubhashes(
            sources: sourcesHash,
            resources: resourcesHash,
            copyFiles: copyFilesHash,
            coreDataModels: coreDataModelHash,
            targetScripts: targetScriptsHash,
            dependencies: dependenciesHash.hash,
            environment: environmentHash,
            headers: headersHash,
            deploymentTarget: deploymentTargetHash,
            infoPlist: infoPlistHash,
            entitlements: entitlementsHash,
            projectSettings: projectSettingsHash,
            targetSettings: settingsHash,
            buildableFolders: buildableFoldersHash,
            additionalStrings: additionalStrings,
            embeddedProductReferences: embeddedProductReferencesHash
        )

        return TargetContentHash(
            hash: hash,
            hashedPaths: hashedPaths,
            subhashes: subhashes
        )
    }
}
