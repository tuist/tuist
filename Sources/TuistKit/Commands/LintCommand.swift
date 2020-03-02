import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum LintCommandError: FatalError, Equatable {
    /// Thrown when neither a workspace or a project is found in the given path.
    case manifestNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .manifestNotFound:
            return .abort
        }
    }

    /// Description
    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find Project.swift nor Workspace.swift at \(path.pathString)"
        }
    }
}

/// Command that builds a target from the project in the current directory.
class LintCommand: NSObject, Command {
    /// Command name.
    static var command: String = "lint"

    /// Command description.
    static var overview: String = "Lints a workspace or a project that check whether they are well configured."

    /// Graph linter
    private let graphLinter: GraphLinting
    private let environmentLinter: EnvironmentLinting
    private let manifestLoading: ManifestLoading
    private let graphLoader: GraphLoading
    let pathArgument: OptionArgument<String>

    /// Default constructor.
    public required convenience init(parser: ArgumentParser) {
        let manifestLoader = ManifestLoader()
        let generatorModelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                                        manifestLinter: AnyManifestLinter())
        self.init(graphLinter: GraphLinter(),
                  environmentLinter: EnvironmentLinter(),
                  manifestLoading: manifestLoader,
                  graphLoader: GraphLoader(modelLoader: generatorModelLoader),
                  parser: parser)
    }

    init(graphLinter: GraphLinting,
         environmentLinter: EnvironmentLinting,
         manifestLoading: ManifestLoading,
         graphLoader: GraphLoading,
         parser: ArgumentParser) {
        let subParser = parser.add(subparser: LintCommand.command, overview: LintCommand.overview)
        self.graphLinter = graphLinter
        self.environmentLinter = environmentLinter
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory that contains the workspace or project to be linted",
                                     completion: .filename)
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)

        // Load graph
        let manifests = manifestLoading.manifests(at: path)
        var graph: Graphing!

        Printer.shared.print(section: "Loading the dependency graph")
        if manifests.contains(.workspace) {
            Printer.shared.print("Loading workspace at \(path.pathString)")
            (graph, _) = try graphLoader.loadWorkspace(path: path)
        } else if manifests.contains(.project) {
            Printer.shared.print("Loading project at \(path.pathString)")
            (graph, _) = try graphLoader.loadProject(path: path)
        } else {
            throw LintCommandError.manifestNotFound(path)
        }

        Printer.shared.print(section: "Running linters")
        let config = try graphLoader.loadTuistConfig(path: path)

        var issues: [LintingIssue] = []
        Printer.shared.print("Linting the environment")
        issues.append(contentsOf: try environmentLinter.lint(config: config))
        Printer.shared.print("Linting the loaded dependency graph")
        issues.append(contentsOf: graphLinter.lint(graph: graph))

        if issues.isEmpty {
            Printer.shared.print(success: "No linting issues found")
        } else {
            try issues.printAndThrowIfNeeded()
        }
    }

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
