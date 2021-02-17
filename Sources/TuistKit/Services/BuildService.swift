import Foundation
import RxBlocking
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGraph
import TuistSupport

enum BuildServiceError: FatalError {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutBuildableTargets(scheme: String)

    // Error description
    var description: String {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutBuildableTargets(scheme):
            return "The scheme \(scheme) cannot be built because it contains no buildable targets."
        }
    }

    // Error type
    var type: ErrorType {
        switch self {
        case .schemeNotFound:
            return .abort
        case .schemeWithoutBuildableTargets:
            return .abort
        }
    }
}

final class BuildService {
    /// Generator
    let generator: Generating

    /// Xcode build controller.
    let xcodebuildController: XcodeBuildControlling

    /// Build graph inspector.
    let buildGraphInspector: BuildGraphInspecting

    init(generator: Generating = Generator(contentHasher: CacheContentHasher()),
         xcodebuildController: XcodeBuildControlling = XcodeBuildController(),
         buildGraphInspector: BuildGraphInspecting = BuildGraphInspector())
    {
        self.generator = generator
        self.xcodebuildController = xcodebuildController
        self.buildGraphInspector = buildGraphInspector
    }

    func run(
        schemeName: String?,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        path: AbsolutePath
    ) throws {
        let graph: ValueGraph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = ValueGraph(graph: try generator.generateWithGraph(path: path, projectOnly: false).1)
        } else {
            graph = ValueGraph(graph: try generator.load(path: path))
        }
        let graphTraverser = ValueGraphTraverser(graph: graph)

        let buildableSchemes = buildGraphInspector.buildableSchemes(graphTraverser: graphTraverser)

        logger.log(level: .debug, "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))")

        if let schemeName = schemeName {
            guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                throw BuildServiceError.schemeNotFound(scheme: schemeName, existing: buildableSchemes.map(\.name))
            }
            try buildScheme(scheme: scheme, graphTraverser: graphTraverser, path: path, clean: clean, configuration: configuration)
        } else {
            var cleaned: Bool = false
            // Run only buildable entry schemes when specific schemes has not been passed
            let buildableEntrySchemes = buildGraphInspector.buildableEntrySchemes(graphTraverser: graphTraverser)
            try buildableEntrySchemes.forEach {
                try buildScheme(scheme: $0, graphTraverser: graphTraverser, path: path, clean: !cleaned && clean, configuration: configuration)
                cleaned = true
            }
        }

        logger.log(level: .notice, "The project built successfully", metadata: .success)
    }

    // MARK: - private

    private func buildScheme(scheme: Scheme, graphTraverser: GraphTraversing, path: AbsolutePath, clean: Bool, configuration: String?) throws {
        logger.log(level: .notice, "Building scheme \(scheme.name)", metadata: .section)
        guard let (project, target) = buildGraphInspector.buildableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw BuildServiceError.schemeWithoutBuildableTargets(scheme: scheme.name)
        }
        let workspacePath = try buildGraphInspector.workspacePath(directory: path)!
        let buildArguments = buildGraphInspector.buildArguments(project: project, target: target, configuration: configuration, skipSigning: false)
        _ = try xcodebuildController.build(.workspace(workspacePath),
                                           scheme: scheme.name,
                                           clean: clean,
                                           arguments: buildArguments)
            .printFormattedOutput()
            .toBlocking()
            .last()
    }
}
