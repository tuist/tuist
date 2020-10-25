import Foundation
import RxBlocking
import TSCBasic
import TuistAutomation
import TuistCore
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

    init(generator: Generating = Generator(),
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
        let graph: Graph
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            graph = try generator.generateWithGraph(path: path, projectOnly: false).1
        } else {
            graph = try generator.load(path: path)
        }

        let buildableSchemes = buildGraphInspector.buildableSchemes(graph: graph)

        logger.log(level: .debug, "Found the following buildable schemes: \(buildableSchemes.map(\.name).joined(separator: ", "))")

        if let schemeName = schemeName {
            guard let scheme = buildableSchemes.first(where: { $0.name == schemeName }) else {
                throw BuildServiceError.schemeNotFound(scheme: schemeName, existing: buildableSchemes.map(\.name))
            }
            try buildScheme(scheme: scheme, graph: graph, path: path, clean: clean, configuration: configuration)
        } else {
            var cleaned: Bool = false
            // Run only buildable entry schemes when specific schemes has not been passed
            let buildableEntrySchemes = buildGraphInspector.buildableEntrySchemes(graph: graph)
            try buildableEntrySchemes.forEach {
                try buildScheme(scheme: $0, graph: graph, path: path, clean: !cleaned && clean, configuration: configuration)
                cleaned = true
            }
        }

        logger.log(level: .notice, "The project built successfully", metadata: .success)
    }

    // MARK: - private

    private func buildScheme(scheme: Scheme, graph: Graph, path: AbsolutePath, clean: Bool, configuration: String?) throws {
        logger.log(level: .notice, "Building scheme \(scheme.name)", metadata: .section)
        guard let buildableTarget = buildGraphInspector.buildableTarget(scheme: scheme, graph: graph) else {
            throw BuildServiceError.schemeWithoutBuildableTargets(scheme: scheme.name)
        }
        let workspacePath = try buildGraphInspector.workspacePath(directory: path)!
        _ = try xcodebuildController.build(.workspace(workspacePath),
                                           scheme: scheme.name,
                                           clean: clean,
                                           arguments: buildGraphInspector.buildArguments(target: buildableTarget, configuration: configuration))
            .printFormattedOutput()
            .toBlocking()
            .last()
    }
}
