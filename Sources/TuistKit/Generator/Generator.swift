import Basic
import Foundation
import TuistCore

struct GeneratorConfig {
    static let `default` = GeneratorConfig()

    var options: GenerationOptions
    var directory: GenerationDirectory

    init(options: GenerationOptions = GenerationOptions(),
         directory: GenerationDirectory = .manifest) {
        self.options = options
        self.directory = directory
    }
}

protocol Generating {
    func generateProject(at path: AbsolutePath, config: GeneratorConfig, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath
    func generateWorkspace(at path: AbsolutePath, config: GeneratorConfig, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath
}

extension Generating {
    func generate(at path: AbsolutePath,
                  config: GeneratorConfig,
                  manifestLoader: GraphManifestLoading) throws -> AbsolutePath {
        let manifests = manifestLoader.manifests(at: path)
        let workspaceFiles: [AbsolutePath] = [Manifest.workspace, Manifest.setup]
            .compactMap { try? manifestLoader.manifestPath(at: path, manifest: $0) }

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, config: config, workspaceFiles: workspaceFiles)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, config: config, workspaceFiles: workspaceFiles)
        } else {
            throw GraphManifestLoaderError.manifestNotFound(path)
        }
    }
}

class Generator: Generating {
    private let graphLoader: GraphLoading
    private let workspaceGenerator: WorkspaceGenerating

    init(system: Systeming = System(),
         printer: Printing = Printer(),
         fileHandler: FileHandling = FileHandler(),
         modelLoader: GeneratorModelLoading) {
        graphLoader = GraphLoader(printer: printer, modelLoader: modelLoader)
        workspaceGenerator = WorkspaceGenerator(system: system,
                                                printer: printer,
                                                projectDirectoryHelper: ProjectDirectoryHelper(),
                                                fileHandler: fileHandler)
    }

    func generateProject(at path: AbsolutePath,
                         config: GeneratorConfig,
                         workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        let (graph, project) = try graphLoader.loadProject(path: path)

        let workspace = Workspace(name: project.name,
                                  projects: graph.projects.map(\.path),
                                  additionalFiles: workspaceFiles.map(Workspace.Element.file))

        return try workspaceGenerator.generate(workspace: workspace,
                                               path: path,
                                               graph: graph,
                                               options: config.options,
                                               directory: config.directory)
    }

    func generateWorkspace(at path: AbsolutePath,
                           config: GeneratorConfig,
                           workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        let (graph, workspace) = try graphLoader.loadWorkspace(path: path)

        let updatedWorkspace = workspace.adding(files: workspaceFiles)

        return try workspaceGenerator.generate(workspace: updatedWorkspace,
                                               path: path,
                                               graph: graph,
                                               options: config.options,
                                               directory: config.directory)
    }
}
