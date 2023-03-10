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
        externalDependencies: [TuistGraph.Platform: [String: [TuistGraph.TargetDependency]]]
    ) throws -> TuistGraph.Target {
        let name = manifest.name
        let platform = try TuistGraph.Platform.from(manifest: manifest.platform)
        let product = TuistGraph.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistGraph.DeploymentTarget.from(manifest: $0) }

        let dependencies = try manifest.dependencies.flatMap {
            try TuistGraph.TargetDependency.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                externalDependencies: externalDependencies,
                platform: platform
            )
        }

        let infoPlist = try TuistGraph.InfoPlist.from(manifest: manifest.infoPlist, generatorPaths: generatorPaths)
        let entitlements = try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }

        let settings = try manifest.settings.map { try TuistGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }

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

        let environment = manifest.environment
        let launchArguments = manifest.launchArguments.map(LaunchArgument.from)

        let playgrounds = sourcesPlaygrounds + resourcesPlaygrounds

        let additionalFiles = try manifest.additionalFiles
            .flatMap { try TuistGraph.FileElement.from(manifest: $0, generatorPaths: generatorPaths) }

        let buildRules = manifest.buildRules.map {
            TuistGraph.BuildRule.from(manifest: $0)
        }

        return TuistGraph.Target(
            name: name,
            platform: platform,
            product: product,
            productName: productName,
            bundleId: bundleId,
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environment: environment,
            launchArguments: launchArguments,
            filesGroup: .group(name: "Project"),
            dependencies: dependencies,
            playgrounds: playgrounds,
            additionalFiles: additionalFiles,
            buildRules: buildRules
        )
    }

    // MARK: - Fileprivate

    fileprivate static func resourcesAndOthers(
        manifest: ProjectDescription.Target,
        generatorPaths: GeneratorPaths
        // swiftlint:disable:next large_tuple
    ) throws -> (
        resources: [TuistGraph.ResourceFileElement],
        playgrounds: [AbsolutePath],
        coreDataModels: [AbsolutePath],
        invalidResourceGlobs: [InvalidGlob]
    ) {
        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistGraph.Target.isResource(path: path)
        }

        var invalidResourceGlobs: [InvalidGlob] = []
        var filteredResources: [TuistGraph.ResourceFileElement] = []
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

        allResources
            .forEach { fileElement in
                switch fileElement {
                case .folderReference: filteredResources.append(fileElement)
                case let .file(path, _):
                    if path.extension == "playground" {
                        playgrounds.insert(path)
                    } else if path.extension == "xcdatamodeld" {
                        coreDataModels.insert(path)
                    } else {
                        filteredResources.append(fileElement)
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
                codeGen: mappedCodeGen
            )
        } ?? [])

        allSources.forEach { sourceFile in
            if sourceFile.path.extension == "playground" {
                playgrounds.insert(sourceFile.path)
            } else {
                sourcesWithoutPlaygrounds.append(sourceFile)
            }
        }

        return (sources: sourcesWithoutPlaygrounds, playgrounds: Array(playgrounds))
    }
}
