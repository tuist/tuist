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
    func generateProject(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath
    func generateWorkspace(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath
}

extension Generating {
    func generate(at path: AbsolutePath,
                  config: GeneratorConfig,
                  manifestLoader: GraphManifestLoading) throws -> AbsolutePath {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, config: config)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, config: config)
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

    func generateProject(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath {
        let graph = try graphLoader.loadProject(path: path)

        return try workspaceGenerator.generate(path: path,
                                               graph: graph,
                                               options: config.options,
                                               directory: config.directory)
    }

    func generateWorkspace(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath {
        let graph = try graphLoader.loadWorkspace(path: path)

        return try workspaceGenerator.generate(path: path,
                                               graph: graph,
                                               options: config.options,
                                               directory: config.directory)
    }
}
