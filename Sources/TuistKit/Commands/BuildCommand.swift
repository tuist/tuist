import Basic
import Foundation
import RxBlocking
import RxSwift
import SPMUtility
import TuistAutomation
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum BuildCommandError: FatalError {
    var type: ErrorType { .abort }

    var description: String {
        switch self {
        case let .moreThanOneWorkspace(path):
            return "There is more than one workspace at \(path.pathString) when only one is expected"
        case let .noWorkspaceFound(path):
            return "There was no workspace found at \(path.pathString). Make sure that the project is generated beforehand, or that build is executed without the '--no-generate' argument."
        }
    }

    case moreThanOneWorkspace(AbsolutePath)
    case noWorkspaceFound(AbsolutePath)
}

/// Command that builds a target from the project in the current directory.
class BuildCommand: NSObject, Command {
    /// Command name.
    static var command: String = "build"

    /// Command description.
    static var overview: String = "Builds a scheme from the project or workspace in the current directory."

    /// Project generator.
    private let generator: Generating

    /// Manifest loader.
    private let manifestLoader: ManifestLoading

    /// Xcode build controller.
    private let xcodeBuildController: XcodeBuildControlling

    /// Graph loader.
    private let graphLoader: GraphLoading

    /// Scheme to be built.
    private let schemeArgument: PositionalArgument<String>

    /// The path to the directory that contains the definitino of the project.
    private let pathArgument: OptionArgument<String>

    /// The argument indicates whether the project should be generated or not
    private let noGenerateArgument: OptionArgument<Bool>

    /// An argument to indicate whether Derived Data should be cleaned before building.
    private let cleanArgument: OptionArgument<Bool>

    required convenience init(parser: ArgumentParser) {
        let manifestLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let generatorModelLoader = GeneratorModelLoader(manifestLoader: manifestLoader, manifestLinter: manifestLinter)
        self.init(generator: Generator(),
                  manifestLoader: ManifestLoader(),
                  xcodeBuildController: XcodeBuildController(),
                  graphLoader: GraphLoader(modelLoader: generatorModelLoader),
                  parser: parser)
    }

    init(generator: Generating,
         manifestLoader: ManifestLoading,
         xcodeBuildController: XcodeBuildControlling,
         graphLoader: GraphLoading,
         parser: ArgumentParser) {
        let subparser = parser.add(subparser: BuildCommand.command, overview: BuildCommand.overview)
        schemeArgument = subparser.add(positional: "scheme", kind: String.self, optional: false, usage: "The project scheme to be built", completion: Optional.none)
        pathArgument = subparser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the directory that contains the workspace or project to be built",
                                     completion: .filename)
        noGenerateArgument = subparser.add(option: "--no-generate",
                                           shortName: "-n",
                                           kind: Bool.self,
                                           usage: "When passed, the workspace doesn't get generated before building the scheme",
                                           completion: nil)
        cleanArgument = subparser.add(option: "--clean",
                                      shortName: "-c",
                                      kind: Bool.self,
                                      usage: "If true the Derived Data directory is cleaned before building the scheme",
                                      completion: nil)
        self.generator = generator
        self.manifestLoader = manifestLoader
        self.xcodeBuildController = xcodeBuildController
        self.graphLoader = graphLoader
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let scheme = arguments.get(schemeArgument)!

        let graph: Graph
        if noGenerate(arguments: arguments) {
            Printer.shared.print(section: "Loading the dependency graph")
            graph = try graphLoader.load(at: path, manifestLoader: manifestLoader)
        } else {
            (_, graph) = try generator.generateWorkspace(at: path, manifestLoader: manifestLoader)
        }

        let xcodebuildArguments = self.arguments(graph: graph, scheme: scheme)

        // Build
        let workspacePath = try self.workspacePath(at: path)
        let buildTarget = XcodeBuildTarget.workspace(workspacePath)
        Printer.shared.print(section: "Building scheme \(scheme) from workspace \(workspacePath.pathString)")
        _ = try xcodeBuildController.build(buildTarget, scheme: scheme,
                                           clean: clean(arguments: arguments),
                                           arguments: xcodebuildArguments)
            .printFormattedOutput()
            .toBlocking()
            .last()
        Printer.shared.print(success: "Scheme '\(scheme)' built successfully")
    }

    fileprivate func arguments(graph: Graph, scheme: String) -> [XcodeBuildArgument] {
        guard let target = graph.targets.first(where: { $0.target.name == scheme })?.target else {
            return []
        }
        let platform = target.platform
        let sdk: String = (platform == .macOS) ? platform.xcodeDeviceSDK : platform.xcodeSimulatorSDK!
        return [.sdk(sdk)]
    }

    fileprivate func noGenerate(arguments: ArgumentParser.Result) -> Bool {
        arguments.get(noGenerateArgument) ?? false
    }

    fileprivate func clean(arguments: ArgumentParser.Result) -> Bool {
        arguments.get(cleanArgument) ?? false
    }

    fileprivate func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    fileprivate func workspacePath(at path: AbsolutePath) throws -> AbsolutePath {
        let workspaces = FileHandler.shared.glob(path, glob: "*.xcworkspace")
        if workspaces.count > 1 {
            throw BuildCommandError.moreThanOneWorkspace(path)
        } else if workspaces.count == 0 {
            throw BuildCommandError.noWorkspaceFound(path)
        } else {
            return workspaces.first!
        }
    }
}
