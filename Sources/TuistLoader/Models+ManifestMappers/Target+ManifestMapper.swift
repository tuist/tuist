import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
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
extension TuistCore.Target {
    /// Maps a ProjectDescription.Target instance into a TuistCore.Target instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the target.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Target, generatorPaths: GeneratorPaths) throws -> TuistCore.Target {
        let name = manifest.name
        let platform = try TuistCore.Platform.from(manifest: manifest.platform)
        let product = TuistCore.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistCore.DeploymentTarget.from(manifest: $0) }

        let dependencies = try manifest.dependencies.map { try TuistCore.Dependency.from(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = try TuistCore.InfoPlist.from(manifest: manifest.infoPlist, generatorPaths: generatorPaths)
        let entitlements = try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }

        let settings = try manifest.settings.map { try TuistCore.Settings.from(manifest: $0, generatorPaths: generatorPaths) }

        let (sources, playgrounds) = try sourcesAndPlaygrounds(manifest: manifest, targetName: name, generatorPaths: generatorPaths)

        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistCore.Target.isResource(path: path)
        }

        var invalidResourceGlobs: [InvalidGlob] = []

        let resources: [TuistCore.FileElement] = try (manifest.resources ?? []).flatMap { manifest -> [TuistCore.FileElement] in
            do {
                return try TuistCore.FileElement.from(manifest: manifest,
                                                      generatorPaths: generatorPaths,
                                                      includeFiles: resourceFilter)
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                invalidResourceGlobs.append(invalidGlob)
                return []
            }
        }

        if !invalidResourceGlobs.isEmpty {
            throw TargetManifestMapperError.invalidResourcesGlob(targetName: name, invalidGlobs: invalidResourceGlobs)
        }

        let copyFiles = try (manifest.copyFiles ?? []).map {
            try TuistCore.CopyFilesAction.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let headers = try manifest.headers.map { try TuistCore.Headers.from(manifest: $0, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistCore.CoreDataModel.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let actions = try manifest.actions.map {
            try TuistCore.TargetAction.from(manifest: $0, generatorPaths: generatorPaths)
        }

        let environment = manifest.environment
        let launchArguments = manifest.launchArguments.map(LaunchArgument.from)

        return TuistCore.Target(name: name,
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

    fileprivate static func sourcesAndPlaygrounds(manifest: ProjectDescription.Target, targetName: String, generatorPaths: GeneratorPaths) throws -> (sources: [TuistCore.SourceFile], playgrounds: [AbsolutePath]) {
        var sourcesWithoutPlaygrounds: [TuistCore.SourceFile] = []
        var playgrounds: Set<AbsolutePath> = []

        // Sources
        let allSources = try TuistCore.Target.sources(targetName: targetName, sources: manifest.sources?.globs.map { (glob: ProjectDescription.SourceFileGlob) in
            let globPath = try generatorPaths.resolve(path: glob.glob).pathString
            let excluding: [String] = try glob.excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
            return TuistCore.SourceFileGlob(glob: globPath, excluding: excluding, compilerFlags: glob.compilerFlags)
        } ?? [])

        
        allSources.forEach { sourceFile in
            if sourceFile.path.pathString.range(of: "\\.playground/Contents\\.swift$", options: .regularExpression) == nil {
                sourcesWithoutPlaygrounds.append(sourceFile)
            } else {
                playgrounds.insert(sourceFile.path.parentDirectory)
            }
        }

        return (sources: sourcesWithoutPlaygrounds, playgrounds: Array(playgrounds))
    }
}
