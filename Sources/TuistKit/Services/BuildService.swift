import Foundation
import TSCBasic
import TuistAutomation
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport
import TSCUtility

enum BuildServiceError: FatalError {
    case workspaceNotFound(path: String)
    case schemeWithoutBuildableTargets(scheme: String)
    case schemeNotFound(scheme: String, existing: [String])
    
    var description: String {
        switch self {
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path)"
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        }
    }
    
    var type: ErrorType {
        switch self {
        case .workspaceNotFound:
            return .bug
        case .schemeNotFound,
                .schemeWithoutBuildableTargets:
            return .abort
        }
    }
}

public final class BuildService {
    private let generatorFactory: GeneratorFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding
    private let configLoader: ConfigLoading
    
    public init(
        generatorFactory: GeneratorFactorying = GeneratorFactory(),
        buildGraphInspector: BuildGraphInspecting = BuildGraphInspector(),
        targetBuilder: TargetBuilding = TargetBuilder(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.configLoader = configLoader
    }
    
    // swiftlint:disable:next function_body_length
    public func run(
        schemeNames: [String],
        generate: Bool,
        clean: Bool,
        configuration: String?,
        buildOutputPath: AbsolutePath?,
        derivedDataPath: String?,
        path: AbsolutePath,
        device: String?,
        platform: TuistGraph.Platform?,
        osVersion: Version?,
        rosetta: Bool,
        generateOnly: Bool,
        generator: ((Config) throws -> Generating)? = nil
    ) async throws {
        let graph: Graph
        let config = try configLoader.loadConfig(path: path)
        let generator = try generator?(config) ?? generatorFactory.default(config: config)
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try await generator.generateWithGraph(path: path).1
        } else {
            graph = try await generator.load(path: path)
        }
        
        if generateOnly {
            return
        }
        
        guard let workspacePath = try buildGraphInspector.workspacePath(directory: path) else {
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
        
        logger.log(
            level: .debug,
            "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))"
        )
        
        let schemesToBuild: [Scheme]
        if schemeNames.isEmpty {
            // Build only buildable entry schemes when no specific schemes are passed
            schemesToBuild = buildGraphInspector.buildableEntrySchemes(graphTraverser: graphTraverser)
        } else {
            schemesToBuild = try schemeNames.compactMap { schemeName in
                guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                    throw BuildServiceError.schemeNotFound(scheme: schemeName, existing: buildableSchemes.map(\.name))
                }
                return scheme
            }
        }
        
        var cleaned = false
        
        for scheme in schemesToBuild {
            guard let graphTarget = buildGraphInspector.buildableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
                throw TargetBuilderError.schemeWithoutBuildableTargets(scheme: scheme.name)
            }
            
            let buildPlatform: TuistGraph.Platform
            
            if let platform {
                buildPlatform = platform
                //try TuistGraph.Platform.from(commandLineValue: platform)
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
                osVersion: osVersion,
                rosetta: rosetta,
                graphTraverser: graphTraverser
            )
            cleaned = true
        }
        
        logger.log(level: .notice, "The project built successfully", metadata: .success)
    }
}
