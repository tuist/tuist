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
    /// Maps a ProjectDescription.Target instance into a TuistCore.Target instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the target.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Target, generatorPaths: GeneratorPaths) throws -> TuistGraph.Target {
        let name = manifest.name
        let platform = try TuistGraph.Platform.from(manifest: manifest.platform)
        let product = TuistGraph.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistGraph.DeploymentTarget.from(manifest: $0) }

        let dependencies = try manifest.dependencies.map { try TuistGraph.Dependency.from(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = try TuistGraph.InfoPlist.from(manifest: manifest.infoPlist, generatorPaths: generatorPaths)
        let entitlements = try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }

        let settings = try manifest.settings.map { try TuistGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }

        let (sources, sourcesPlaygrounds) = try sourcesAndPlaygrounds(manifest: manifest, targetName: name, generatorPaths: generatorPaths)

        var (resources, resourcesPlaygrounds, invalidResourceGlobs) = try resourcesAndPlaygrounds(manifest: manifest, generatorPaths: generatorPaths)
        resources = resourcesFlatteningBundles(resources: resources)

        if !invalidResourceGlobs.isEmpty {
            throw TargetManifestMapperError.invalidResourcesGlob(targetName: name, invalidGlobs: invalidResourceGlobs)
        }

        let copyFiles = try (manifest.copyFiles ?? []).map {
            try TuistGraph.CopyFilesAction.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let headers = try manifest.headers.map { try TuistGraph.Headers.from(manifest: $0, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistGraph.CoreDataModel.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let actions = try manifest.actions.map {
            try TuistGraph.TargetAction.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let environment = manifest.environment
        let launchArguments = manifest.launchArguments.map(LaunchArgument.from)

        let playgrounds = sourcesPlaygrounds + resourcesPlaygrounds

        return TuistGraph.Target(name: name,
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
                                 actions: actions,
                                 environment: environment,
                                 launchArguments: launchArguments,
                                 filesGroup: .group(name: "Project"),
                                 dependencies: dependencies,
                                 playgrounds: playgrounds)
    }

    // MARK: - Fileprivate

    // swiftlint:disable line_length
    fileprivate static func resourcesAndPlaygrounds(manifest: ProjectDescription.Target,
                                                    generatorPaths: GeneratorPaths) throws -> (resources: [TuistGraph.FileElement], playgrounds: [AbsolutePath], invalidResourceGlobs: [InvalidGlob])
    {
        // swiftlint:enable line_length
        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistGraph.Target.isResource(path: path)
        }

        var invalidResourceGlobs: [InvalidGlob] = []
        var resourcesWithoutPlaygrounds: [TuistGraph.FileElement] = []
        var playgrounds: Set<AbsolutePath> = []

        let allResources = try (manifest.resources ?? []).flatMap { manifest -> [TuistGraph.FileElement] in
            do {
                return try TuistGraph.FileElement.from(manifest: manifest,
                                                       generatorPaths: generatorPaths,
                                                       includeFiles: resourceFilter)
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                invalidResourceGlobs.append(invalidGlob)
                return []
            }
        }
        allResources.forEach { fileElement in
            switch fileElement {
            case .folderReference: resourcesWithoutPlaygrounds.append(fileElement)
            case let .file(path, _):
                if path.pathString.contains(".playground/") {
                    playgrounds.insert(path.upToComponentMatching(extension: "playground"))
                } else {
                    resourcesWithoutPlaygrounds.append(fileElement)
                }
            }
        }

        return (resources: resourcesWithoutPlaygrounds, playgrounds: Array(playgrounds), invalidResourceGlobs: invalidResourceGlobs)
    }

    fileprivate static func resourcesFlatteningBundles(resources: [TuistGraph.FileElement]) -> [TuistGraph.FileElement] {
        Array(resources.reduce(into: Set<TuistGraph.FileElement>()) { flattenedResources, resourceElement in
            switch resourceElement {
            case let .file(path, _):
                if path.pathString.contains(".bundle/") {
                    flattenedResources.formUnion([.file(path: path.upToComponentMatching(extension: "bundle"))])
                } else {
                    flattenedResources.formUnion([resourceElement])
                }
            case .folderReference:
                flattenedResources.formUnion([resourceElement])
            }
        })
    }

    // swiftlint:disable:next line_length
    fileprivate static func sourcesAndPlaygrounds(manifest: ProjectDescription.Target, targetName: String, generatorPaths: GeneratorPaths) throws -> (sources: [TuistGraph.SourceFile], playgrounds: [AbsolutePath]) {
        var sourcesWithoutPlaygrounds: [TuistGraph.SourceFile] = []
        var playgrounds: Set<AbsolutePath> = []

        // Sources
        let allSources = try TuistGraph.Target.sources(targetName: targetName, sources: manifest.sources?.globs.map { (glob: ProjectDescription.SourceFileGlob) in
            let globPath = try generatorPaths.resolve(path: glob.glob).pathString
            let excluding: [String] = try glob.excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            return TuistGraph.SourceFileGlob(glob: globPath, excluding: excluding, compilerFlags: glob.compilerFlags)
        } ?? [])

        allSources.forEach { sourceFile in
            if sourceFile.path.pathString.contains(".playground/") {
                playgrounds.insert(sourceFile.path.upToComponentMatching(extension: "playground"))
            } else {
                sourcesWithoutPlaygrounds.append(sourceFile)
            }
        }

        return (sources: sourcesWithoutPlaygrounds, playgrounds: Array(playgrounds))
    }
}
