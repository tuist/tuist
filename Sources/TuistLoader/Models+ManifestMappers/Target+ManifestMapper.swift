import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public enum TargetManifestMapperError: FatalError {
    case invalidResourcesGlob(targetName: String, invalidGlobs: [InvalidGlob])

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidResourcesGlob(targetName: targetName, invalidGlobs: invalidGlobs):
            return "The target \(targetName) has the following invalid resource globs:\n" + invalidGlobs.invalidGlobsDescription
        }
    }
}

// swiftlint:disable function_body_length
extension TuistGraph.Target {
    /// Maps a ProjectDescription.Target instance into a TuistGraph.Target instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the target.
    ///   - generatorPaths: Generator paths.
    ///   - externalDependencies: External dependencies graph.
    static func from(
        manifest: ProjectDescription.Target,
        generatorPaths: GeneratorPaths,
        externalDependencies: [String: [TuistGraph.TargetDependency]]
    ) throws -> TuistGraph.Target {
        let name = manifest.name
        let destinations = try TuistGraph.Destination.from(destinations: manifest.destinations)

        let product = TuistGraph.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTargets = manifest.deploymentTargets.map { TuistGraph.DeploymentTargets.from(manifest: $0) } ?? .empty()

        let dependencies = try manifest.dependencies.flatMap {
            try TuistGraph.TargetDependency.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                externalDependencies: externalDependencies
            )
        }

        let infoPlist = try TuistGraph.InfoPlist.from(manifest: manifest.infoPlist, generatorPaths: generatorPaths)

        let entitlements = try TuistGraph.Entitlements.from(manifest: manifest.entitlements, generatorPaths: generatorPaths)

        let settings = try manifest.settings.map { try TuistGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }
        let mergedBinaryType = try TuistGraph.MergedBinaryType.from(manifest: manifest.mergedBinaryType)

        let (sources, sourcesPlaygrounds) = try sourcesAndPlaygrounds(
            manifest: manifest,
            targetName: name,
            generatorPaths: generatorPaths
        )

        let (resources, resourcesPlaygrounds, resourcesCoreDatas, invalidResourceGlobs) = try resourcesAndOthers(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        if !invalidResourceGlobs.isEmpty {
            throw TargetManifestMapperError.invalidResourcesGlob(targetName: name, invalidGlobs: invalidResourceGlobs)
        }

        let copyFiles = try (manifest.copyFiles ?? []).map {
            try TuistGraph.CopyFilesAction.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let headers = try manifest.headers.map { try TuistGraph.Headers.from(
            manifest: $0,
            generatorPaths: generatorPaths,
            productName: manifest.productName
        ) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistGraph.CoreDataModel.from(manifest: $0, generatorPaths: generatorPaths)
        } + resourcesCoreDatas.map { try TuistGraph.CoreDataModel.from(path: $0) }

        let scripts = try manifest.scripts.map {
            try TuistGraph.TargetScript.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let environmentVariables = manifest.environmentVariables.mapValues(EnvironmentVariable.from)
        let launchArguments = manifest.launchArguments.map(LaunchArgument.from)

        let playgrounds = sourcesPlaygrounds + resourcesPlaygrounds

        let additionalFiles = try manifest.additionalFiles
            .flatMap { try TuistGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }

        let buildRules = manifest.buildRules.map {
            TuistGraph.BuildRule.from(manifest: $0)
        }

        return TuistGraph.Target(
            name: name,
            destinations: destinations,
            product: product,
            productName: productName,
            bundleId: bundleId,
            deploymentTargets: deploymentTargets,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environmentVariables: environmentVariables,
            launchArguments: launchArguments,
            filesGroup: .group(name: "Project"),
            dependencies: dependencies,
            playgrounds: playgrounds,
            additionalFiles: additionalFiles,
            buildRules: buildRules,
            mergedBinaryType: mergedBinaryType,
            mergeable: manifest.mergeable
        )
    }

    // MARK: - Fileprivate

    fileprivate static func resourcesAndOthers(
        manifest: ProjectDescription.Target,
        generatorPaths: GeneratorPaths
        // swiftlint:disable:next large_tuple
    ) throws -> (
        resources: TuistGraph.ResourceFileElements,
        playgrounds: [AbsolutePath],
        coreDataModels: [AbsolutePath],
        invalidResourceGlobs: [InvalidGlob]
    ) {
        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistGraph.Target.isResource(path: path)
        }

        let privacyManifest: TuistGraph.PrivacyManifest? = manifest.resources?.privacyManifest.map {
            return TuistGraph.PrivacyManifest(
                tracking: $0.tracking,
                trackingDomains: $0.trackingDomains,
                collectedDataTypes: $0.collectedDataTypes.map { $0.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }},
                accessedApiTypes: $0.accessedApiTypes.map { $0.mapValues { TuistGraph.Plist.Value.from(manifest: $0) }}
            )
        }

        var invalidResourceGlobs: [InvalidGlob] = []
        var filteredResources: TuistGraph.ResourceFileElements = .init([], privacyManifest: privacyManifest)
        var playgrounds: Set<AbsolutePath> = []
        var coreDataModels: Set<AbsolutePath> = []

        let allResources = try (manifest.resources?.resources ?? []).flatMap { manifest -> [TuistGraph.ResourceFileElement] in
            do {
                return try TuistGraph.ResourceFileElement.from(
                    manifest: manifest,
                    generatorPaths: generatorPaths,
                    includeFiles: resourceFilter
                )
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                invalidResourceGlobs.append(invalidGlob)
                return []
            }
        }

        for fileElement in allResources {
            switch fileElement {
            case .folderReference: filteredResources.resources.append(fileElement)
            case let .file(path, _, _):
                if path.extension == "playground" {
                    playgrounds.insert(path)
                } else if path.extension == "xcdatamodeld" {
                    coreDataModels.insert(path)
                } else {
                    filteredResources.resources.append(fileElement)
                }
            }
        }

        return (
            resources: filteredResources,
            playgrounds: Array(playgrounds),
            coreDataModels: Array(coreDataModels),
            invalidResourceGlobs: invalidResourceGlobs
        )
    }

    fileprivate static func sourcesAndPlaygrounds(
        manifest: ProjectDescription.Target,
        targetName: String,
        generatorPaths: GeneratorPaths
    ) throws -> (sources: [TuistGraph.SourceFile], playgrounds: [AbsolutePath]) {
        var sourcesWithoutPlaygrounds: [TuistGraph.SourceFile] = []
        var playgrounds: Set<AbsolutePath> = []

        // Sources
        let allSources = try TuistGraph.Target.sources(targetName: targetName, sources: manifest.sources?.globs.map { glob in
            let globPath = try generatorPaths.resolve(path: glob.glob).pathString
            let excluding: [String] = try glob.excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            let mappedCodeGen = glob.codeGen.map(TuistGraph.FileCodeGen.from)
            return TuistGraph.SourceFileGlob(
                glob: globPath,
                excluding: excluding,
                compilerFlags: glob.compilerFlags,
                codeGen: mappedCodeGen,
                compilationCondition: glob.compilationCondition?.asGraphCondition
            )
        } ?? [])

        for sourceFile in allSources {
            if sourceFile.path.extension == "playground" {
                playgrounds.insert(sourceFile.path)
            } else {
                sourcesWithoutPlaygrounds.append(sourceFile)
            }
        }

        return (sources: sourcesWithoutPlaygrounds, playgrounds: Array(playgrounds))
    }
    // swiftlint:enable function_body_length
}
