import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

public enum TargetManifestMapperError: FatalError, Equatable {
    case invalidResourcesGlob(targetName: String, invalidGlobs: [InvalidGlob])
    case nonSpecificGeneratedResource(targetName: String, generatedSource: AbsolutePath)

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidResourcesGlob(targetName: targetName, invalidGlobs: invalidGlobs):
            return "The target \(targetName) has the following invalid resource globs:\n" + invalidGlobs.invalidGlobsDescription
        case let .nonSpecificGeneratedResource(targetName: targetName, generatedSource: generatedSource):
            return "Generated source files must be explicit. The target \(targetName) has a generated source file at \(generatedSource.pathString) that has a glob pattern."
        }
    }
}

// swiftlint:disable function_body_length
extension XcodeGraph.Target {
    /// Maps a ProjectDescription.Target instance into a XcodeGraph.Target instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of  the target.
    ///   - generatorPaths: Generator paths.
    ///   - externalDependencies: External dependencies graph.
    static func from(
        manifest: ProjectDescription.Target,
        generatorPaths: GeneratorPaths,
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        fileSystem: FileSysteming,
        type: TargetType
    ) async throws -> XcodeGraph.Target {
        let name = manifest.name
        let destinations = try XcodeGraph.Destination.from(destinations: manifest.destinations)

        let product = XcodeGraph.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTargets = manifest.deploymentTargets.map { XcodeGraph.DeploymentTargets.from(manifest: $0) } ?? .empty()

        let dependencies = try manifest.dependencies.flatMap {
            try XcodeGraph.TargetDependency.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                externalDependencies: externalDependencies
            )
        }

        let infoPlist = try XcodeGraph.InfoPlist.from(manifest: manifest.infoPlist, generatorPaths: generatorPaths)

        let entitlements = try XcodeGraph.Entitlements.from(manifest: manifest.entitlements, generatorPaths: generatorPaths)

        let settings = try manifest.settings.map { try XcodeGraph.Settings.from(manifest: $0, generatorPaths: generatorPaths) }
        let mergedBinaryType = try XcodeGraph.MergedBinaryType.from(manifest: manifest.mergedBinaryType)

        let (sources, sourcesPlaygrounds) = try await sourcesAndPlaygrounds(
            manifest: manifest,
            targetName: name,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        let (resources, resourcesPlaygrounds, resourcesCoreDatas, invalidResourceGlobs) = try await resourcesAndOthers(
            manifest: manifest,
            generatorPaths: generatorPaths,
            fileSystem: fileSystem
        )

        if !invalidResourceGlobs.isEmpty {
            throw TargetManifestMapperError.invalidResourcesGlob(targetName: name, invalidGlobs: invalidResourceGlobs)
        }

        let copyFiles = try await (manifest.copyFiles ?? []).concurrentMap {
            try await XcodeGraph.CopyFilesAction.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        }

        let headers: XcodeGraph.Headers?
        if let manifestHeaders = manifest.headers {
            headers = try await XcodeGraph.Headers.from(
                manifest: manifestHeaders,
                generatorPaths: generatorPaths,
                productName: manifest.productName,
                fileSystem: fileSystem
            )
        } else {
            headers = nil
        }

        let coreDataModels = try await manifest.coreDataModels.concurrentMap {
            try await XcodeGraph.CoreDataModel.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        } + resourcesCoreDatas.concurrentMap {
            try await XcodeGraph.CoreDataModel.from(
                path: $0,
                fileSystem: fileSystem
            )
        }

        let scripts = try await manifest.scripts.concurrentMap {
            try await XcodeGraph.TargetScript.from(
                manifest: $0,
                generatorPaths: generatorPaths,
                fileSystem: fileSystem
            )
        }

        let environmentVariables = manifest.environmentVariables.mapValues(EnvironmentVariable.from)
        let launchArguments = manifest.launchArguments.map(LaunchArgument.from)

        let playgrounds = sourcesPlaygrounds + resourcesPlaygrounds

        let additionalFiles = try await manifest.additionalFiles
            .concurrentMap {
                try await XcodeGraph.FileElement.from(
                    manifest: $0,
                    generatorPaths: generatorPaths,
                    fileSystem: fileSystem
                )
            }
            .flatMap { $0 }

        let buildRules = manifest.buildRules.map {
            XcodeGraph.BuildRule.from(manifest: $0)
        }

        let onDemandResourcesTags = manifest.onDemandResourcesTags.map {
            XcodeGraph.OnDemandResourcesTags(initialInstall: $0.initialInstall, prefetchOrder: $0.prefetchOrder)
        }

        return XcodeGraph.Target(
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
            mergeable: manifest.mergeable,
            onDemandResourcesTags: onDemandResourcesTags,
            type: type
        )
    }

    // MARK: - Fileprivate

    fileprivate static func resourcesAndOthers(
        manifest: ProjectDescription.Target,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
        // swiftlint:disable:next large_tuple
    ) async throws -> (
        resources: XcodeGraph.ResourceFileElements,
        playgrounds: [AbsolutePath],
        coreDataModels: [AbsolutePath],
        invalidResourceGlobs: [InvalidGlob]
    ) {
        let resourceFilter = { (path: AbsolutePath) -> Bool in
            XcodeGraph.Target.isResource(path: path)
        }

        let privacyManifest: XcodeGraph.PrivacyManifest? = manifest.resources?.privacyManifest.map {
            return XcodeGraph.PrivacyManifest(
                tracking: $0.tracking,
                trackingDomains: $0.trackingDomains,
                collectedDataTypes: $0.collectedDataTypes.map { $0.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }},
                accessedApiTypes: $0.accessedApiTypes.map { $0.mapValues { XcodeGraph.Plist.Value.from(manifest: $0) }}
            )
        }

        var filteredResources: XcodeGraph.ResourceFileElements = .init([], privacyManifest: privacyManifest)
        var playgrounds: Set<AbsolutePath> = []
        var coreDataModels: Set<AbsolutePath> = []

        let result = try await (manifest.resources?.resources ?? []).concurrentMap { manifest async throws -> (
            [XcodeGraph.ResourceFileElement],
            InvalidGlob?
        ) in
            do {
                return (
                    try await XcodeGraph.ResourceFileElement.from(
                        manifest: manifest,
                        generatorPaths: generatorPaths,
                        fileSystem: fileSystem,
                        includeFiles: resourceFilter
                    ),
                    nil
                )
            } catch let GlobError.nonExistentDirectory(invalidGlob) {
                return ([], invalidGlob)
            }
        }
        let allResources = result.map(\.0).flatMap { $0 }
        let invalidResourceGlobs = result.compactMap(\.1)

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
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> (sources: [XcodeGraph.SourceFile], playgrounds: [AbsolutePath]) {
        var sourcesWithoutPlaygrounds: [XcodeGraph.SourceFile] = []
        var playgrounds: Set<AbsolutePath> = []

        // Sources
        let globSources = try await XcodeGraph.Target.sources(
            targetName: targetName,
            sources: manifest.sources?.globs
                .filter { $0.type == .alwaysPresent }
                .map { glob in
                    let globPath = try generatorPaths.resolve(path: glob.glob).pathString
                    let excluding: [String] = try glob.excluding.compactMap { try generatorPaths.resolve(path: $0).pathString }
                    let mappedCodeGen = glob.codeGen.map(XcodeGraph.FileCodeGen.from)
                    return XcodeGraph.SourceFileGlob(
                        glob: globPath,
                        excluding: excluding,
                        compilerFlags: glob.compilerFlags,
                        codeGen: mappedCodeGen,
                        compilationCondition: glob.compilationCondition?.asGraphCondition
                    )
                } ?? [],
            fileSystem: fileSystem
        )

        let scriptGeneratedSources = try manifest.sources?.globs
            .filter { $0.type == .generated }
            .map { generated in
                let pathString = try generatorPaths.resolve(path: generated.glob).pathString
                let path = try AbsolutePath(validating: pathString)
                if path.isGlobPath {
                    throw TargetManifestMapperError.nonSpecificGeneratedResource(targetName: targetName, generatedSource: path)
                }
                let mappedCodeGen = generated.codeGen.map(XcodeGraph.FileCodeGen.from)
                return XcodeGraph.SourceFile(
                    path: path,
                    compilerFlags: generated.compilerFlags,
                    codeGen: mappedCodeGen,
                    compilationCondition: generated.compilationCondition?.asGraphCondition
                )
            }

        let allSources = globSources + (scriptGeneratedSources ?? [])

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
