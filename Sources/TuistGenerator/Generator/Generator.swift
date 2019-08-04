import Basic
import Foundation
import TuistCore

/// A component responsible for generating Xcode projects & workspaces
public protocol Generating {
    /// Generates an Xcode project at a given path. Only the specified project is generated (excluding its dependencies).
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode project should be generated
    /// - Returns: An absolute path to the generated Xcode project many of which adopt `FatalError`
    /// - Throws: Errors encountered during the generation process
    /// - seealso: TuistCore.FatalError
    func generateProject(at path: AbsolutePath) throws -> AbsolutePath

    /// Generate an Xcode workspace for the project at a given path. All the project's dependencies will also be generated and included.
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode workspace should be generated
    ///           (e.g. /path/to/directory)
    ///   - workspaceFiles: Additional files to include in the final generated workspace
    /// - Returns: An absolute path to the generated Xcode workspace
    ///            (e.g. /path/to/directory/project.xcodeproj)
    /// - Throws: Errors encountered during the generation process
    ///           many of which adopt `FatalError`
    /// - seealso: TuistCore.FatalError
    @discardableResult
    func generateProjectWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath

    /// Generate an Xcode workspace at a given path. All referenced projects and their dependencies will be generated and included.
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode workspace should be generated
    ///           (e.g. /path/to/directory)
    ///   - workspaceFiles: Additional files to include in the final generated workspace
    /// - Returns: An absolute path to the generated Xcode workspace
    ///            (e.g. /path/to/directory/project.xcodeproj)
    /// - Throws: Errors encountered during the generation process
    ///           many of which adopt `FatalError`
    /// - seealso: TuistCore.FatalError
    @discardableResult
    func generateWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath
}

/// A default implementation of `Generating`
///
/// - seealso: Generating
/// - seealso: GeneratorModelLoading
public class Generator: Generating {
    private let graphLoader: GraphLoading
    private let workspaceGenerator: WorkspaceGenerating
    private let projectGenerator: ProjectGenerating

    public convenience init(system: Systeming = System(),
                            printer: Printing = Printer(),
                            fileHandler: FileHandling = FileHandler(),
                            defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider(),
                            modelLoader: GeneratorModelLoading) {
        let graphLinter = GraphLinter(fileHandler: fileHandler)
        let graphLoader = GraphLoader(linter: graphLinter, printer: printer, fileHandler: fileHandler, modelLoader: modelLoader)
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator,
                                                printer: printer,
                                                system: system,
                                                fileHandler: fileHandler)
        let workspaceStructureGenerator = WorkspaceStructureGenerator(fileHandler: fileHandler)
        let cocoapodsInteractor = CocoaPodsInteractor()
        let workspaceGenerator = WorkspaceGenerator(system: system,
                                                    printer: printer,
                                                    projectGenerator: projectGenerator,
                                                    fileHandler: fileHandler,
                                                    workspaceStructureGenerator: workspaceStructureGenerator,
                                                    cocoapodsInteractor: cocoapodsInteractor)
        self.init(graphLoader: graphLoader,
                  workspaceGenerator: workspaceGenerator,
                  projectGenerator: projectGenerator)
    }

    init(graphLoader: GraphLoading,
         workspaceGenerator: WorkspaceGenerating,
         projectGenerator: ProjectGenerating) {
        self.graphLoader = graphLoader
        self.workspaceGenerator = workspaceGenerator
        self.projectGenerator = projectGenerator
    }

    public func generateProject(at path: AbsolutePath) throws -> AbsolutePath {
        let (graph, project) = try graphLoader.loadProject(path: path)

        let generatedProject = try projectGenerator.generate(project: project,
                                                             graph: graph,
                                                             sourceRootPath: path)
        return generatedProject.path
    }

    public func generateProjectWorkspace(at path: AbsolutePath,
                                         workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        let tuistConfig = try graphLoader.loadTuistConfig(path: path)
        let (graph, project) = try graphLoader.loadProject(path: path)

        let workspace = Workspace(name: project.name,
                                  projects: graph.projectPaths,
                                  additionalFiles: workspaceFiles.map(FileElement.file))

        return try workspaceGenerator.generate(workspace: workspace,
                                               path: path,
                                               graph: graph,
                                               tuistConfig: tuistConfig)
    }

    public func generateWorkspace(at path: AbsolutePath,
                                  workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        let (graph, workspace) = try graphLoader.loadWorkspace(path: path)
        let tuistConfig = try graphLoader.loadTuistConfig(path: path)

        let updatedWorkspace = workspace
            .merging(projects: graph.projectPaths)
            .adding(files: workspaceFiles)

        return try workspaceGenerator.generate(workspace: updatedWorkspace,
                                               path: path,
                                               graph: graph,
                                               tuistConfig: tuistConfig)
    }
}
