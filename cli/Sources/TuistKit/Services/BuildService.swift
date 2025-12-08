import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

enum BuildServiceError: LocalizedError {
    case workspaceNotFound(path: String)
    case schemeWithoutBuildableTargets(scheme: String)
    case schemeNotFound(scheme: String, existing: [String])

    var errorDescription: String? {
        switch self {
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path)"
        case let .schemeNotFound(scheme, existing):
            return
                "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        }
    }
}

public final class BuildService {
    private let generatorFactory: GeneratorFactorying
    private let cacheStorageFactory: CacheStorageFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding
    private let configLoader: ConfigLoading

    public init(
        generatorFactory: GeneratorFactorying,
        cacheStorageFactory: CacheStorageFactorying,
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        targetBuilder: TargetBuilding = TargetBuilder(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.configLoader = configLoader
    }

    // swiftlint:disable:next function_body_length
    public func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: String?,
        path: AbsolutePath,
        device: String?,
        platform: Platform?,
        osVersion: String?,
        rosetta: Bool,
        generateOnly: Bool,
        generator _: ((Tuist) throws -> Generating)? = nil,
        passthroughXcodeBuildArguments: [String]
    ) async throws {
        AlertController.current.warning(.alert(
            "'tuist build' is deprecated in favor of \(.command("tuist xcodebuild"))",
            takeaway: "Run \(.command("tuist generate")) and then build the generated project using the xcodebuild wrapper \(.command("tuist xcodebuild build"))"
        ))
        let graph: Graph
        let config = try await configLoader.loadConfig(path: path)
            .assertingIsGeneratedProjectOrSwiftPackage(
                errorMessageOverride:
                "The 'tuist build' command is for generated projects or Swift packages. Please use 'tuist xcodebuild build' instead."
            )
        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)
        let generator = generatorFactory.building(
            config: config,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            cacheStorage: cacheStorage
        )
        let workspacePath = try await buildGraphInspector.workspacePath(directory: path)
        if generate || workspacePath == nil {
            graph = try await generator.generateWithGraph(
                path: path,
                options: config.project.generatedProject?.generationOptions
            ).1
        } else {
            graph = try await generator.load(
                path: path,
                options: config.project.generatedProject?.generationOptions
            )
        }

        if generateOnly {
            return
        }

        guard let workspacePath = try await buildGraphInspector.workspacePath(directory: path)
        else {
            throw BuildServiceError.workspaceNotFound(path: path.pathString)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let buildableSchemes = buildGraphInspector.buildableSchemes(graphTraverser: graphTraverser)

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: FileHandler.shared.currentPath
            )
        }

        Logger.current.log(
            level: .debug,
            "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))"
        )

        if let schemeName {
            guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                throw BuildServiceError.schemeNotFound(
                    scheme: schemeName, existing: buildableSchemes.map(\.name)
                )
            }

            guard let graphTarget = buildGraphInspector.buildableTarget(
                scheme: scheme, graphTraverser: graphTraverser
            )
            else {
                throw TargetBuilderError.schemeWithoutBuildableTargets(scheme: scheme.name)
            }

            let buildPlatform: XcodeGraph.Platform

            if let platform {
                buildPlatform = platform
            } else {
                buildPlatform = try graphTarget.target.servicePlatform
            }

            try await targetBuilder.buildTarget(
                graphTarget,
                platform: buildPlatform,
                workspacePath: workspacePath,
                scheme: scheme,
                clean: clean,
                configuration: configuration,
                buildOutputPath: buildOutputPath,
                derivedDataPath: derivedDataPath,
                device: device,
                osVersion: osVersion?.version().map { .init(stringLiteral: $0.description) },
                rosetta: rosetta,
                graphTraverser: graphTraverser,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
            )
        } else {
            var cleaned = false
            // Build only buildable entry schemes when specific schemes has not been passed
            let buildableEntrySchemes = buildGraphInspector.buildableEntrySchemes(
                graphTraverser: graphTraverser
            )
            for scheme in buildableEntrySchemes {
                guard let graphTarget = buildGraphInspector.buildableTarget(
                    scheme: scheme, graphTraverser: graphTraverser
                )
                else {
                    throw TargetBuilderError.schemeWithoutBuildableTargets(scheme: scheme.name)
                }

                let buildPlatform: XcodeGraph.Platform

                if let platform {
                    buildPlatform = platform
                } else {
                    buildPlatform = try graphTarget.target.servicePlatform
                }

                try await targetBuilder.buildTarget(
                    graphTarget,
                    platform: buildPlatform,
                    workspacePath: workspacePath,
                    scheme: scheme,
                    clean: !cleaned && clean,
                    configuration: configuration,
                    buildOutputPath: buildOutputPath,
                    derivedDataPath: derivedDataPath,
                    device: device,
                    osVersion: osVersion?.version().map { .init(stringLiteral: $0.description) },
                    rosetta: rosetta,
                    graphTraverser: graphTraverser,
                    passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
                )
                cleaned = true
            }
        }

        AlertController.current.success(.alert("The project built successfully"))
    }
}
