import Basic
import Foundation
import TuistCore
import TuistSupport

/// A component responsible for generating Xcode projects & workspaces
public protocol Generating {
    /// Generates an Xcode project at a given path. Only the specified project is generated (excluding its dependencies).
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode project should be generated
    /// - Returns: An absolute path to the generated Xcode project many of which adopt `FatalError`
    /// - Throws: Errors encountered during the generation process
    /// - seealso: TuistCore.FatalError
    func generateProject(at path: AbsolutePath) throws -> (AbsolutePath, Graphing)

    /// Generates the given project in the same directory where it's defined.
    /// - Parameters:
    ///     - project: The project to be generated.
    ///     - graph: The dependencies graph.
    ///     - sourceRootPath: The path all the files in the Xcode project will be realtived to. When it's nil, it's assumed that all the paths are relative to the directory that contains the manifest.
    ///     - xcodeprojPath: Path where the .xcodeproj directory will be generated. When the attribute is nil, the project is generated in the manifest's directory.
    func generateProject(_ project: Project, graph: Graphing, sourceRootPath: AbsolutePath?, xcodeprojPath: AbsolutePath?) throws -> AbsolutePath

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
    func generateProjectWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> (AbsolutePath, Graphing)

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
    func generateWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> (AbsolutePath, Graphing)
}

/// A default implementation of `Generating`
///
/// - seealso: Generating
/// - seealso: GeneratorModelLoading
public class Generator: Generating {
    private let graphLoader: GraphLoading
    private let graphLinter: GraphLinting
    private let workspaceGenerator: WorkspaceGenerating
    private let projectGenerator: ProjectGenerating

    /// Instance to lint the Tuist configuration against the system.
    private let environmentLinter: EnvironmentLinting

    public convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider(),
                            modelLoader: GeneratorModelLoading) {
        let graphLinter = GraphLinter()
        let graphLoader = GraphLoader(modelLoader: modelLoader)
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator)
        let environmentLinter = EnvironmentLinter()
        let workspaceStructureGenerator = WorkspaceStructureGenerator()
        let cocoapodsInteractor = CocoaPodsInteractor()
        let schemesGenerator = SchemesGenerator()
        let workspaceGenerator = WorkspaceGenerator(projectGenerator: projectGenerator,
                                                    workspaceStructureGenerator: workspaceStructureGenerator,
                                                    cocoapodsInteractor: cocoapodsInteractor,
                                                    schemesGenerator: schemesGenerator)
        self.init(graphLoader: graphLoader,
                  graphLinter: graphLinter,
                  workspaceGenerator: workspaceGenerator,
                  projectGenerator: projectGenerator,
                  environmentLinter: environmentLinter)
    }

    init(graphLoader: GraphLoading,
         graphLinter: GraphLinting,
         workspaceGenerator: WorkspaceGenerating,
         projectGenerator: ProjectGenerating,
         environmentLinter: EnvironmentLinting) {
        self.graphLoader = graphLoader
        self.graphLinter = graphLinter
        self.workspaceGenerator = workspaceGenerator
        self.projectGenerator = projectGenerator
        self.environmentLinter = environmentLinter
    }

    public func generateProject(_ project: Project,
                                graph: Graphing,
                                sourceRootPath: AbsolutePath? = nil,
                                xcodeprojPath: AbsolutePath? = nil) throws -> AbsolutePath {
        /// When the source root path is not given, we assume paths
        /// are relative to the directory that contains the manifest.
        let sourceRootPath = sourceRootPath ?? project.path

        let generatedProject = try projectGenerator.generate(project: project,
                                                             graph: graph,
                                                             sourceRootPath: sourceRootPath,
                                                             xcodeprojPath: xcodeprojPath)
        return generatedProject.path
    }

    public func generateProject(at path: AbsolutePath) throws -> (AbsolutePath, Graphing) {
        let tuistConfig = try graphLoader.loadTuistConfig(path: path)
        try environmentLinter.lint(config: tuistConfig)

        let (graph, project) = try graphLoader.loadProject(path: path)
        try graphLinter.lint(graph: graph).printAndThrowIfNeeded()

        let generatedProject = try projectGenerator.generate(project: project,
                                                             graph: graph,
                                                             sourceRootPath: path,
                                                             xcodeprojPath: nil)
        return (generatedProject.path, graph)
    }

    public func generateProjectWorkspace(at path: AbsolutePath,
                                         workspaceFiles: [AbsolutePath]) throws -> (AbsolutePath, Graphing) {
        let tuistConfig = try graphLoader.loadTuistConfig(path: path)
        try environmentLinter.lint(config: tuistConfig)

        let (graph, project) = try graphLoader.loadProject(path: path)
        try graphLinter.lint(graph: graph).printAndThrowIfNeeded()

        let workspace = Workspace(path: path,
                                  name: project.name,
                                  projects: graph.projectPaths,
                                  additionalFiles: workspaceFiles.map(FileElement.file))

        let workspacePath = try workspaceGenerator.generate(workspace: workspace,
                                                            path: path,
                                                            graph: graph,
                                                            tuistConfig: tuistConfig)
        return (workspacePath, graph)
    }

    public func generateWorkspace(at path: AbsolutePath,
                                  workspaceFiles: [AbsolutePath]) throws -> (AbsolutePath, Graphing) {
        let tuistConfig = try graphLoader.loadTuistConfig(path: path)
        try environmentLinter.lint(config: tuistConfig)
        let (graph, workspace) = try graphLoader.loadWorkspace(path: path)
        try graphLinter.lint(graph: graph).printAndThrowIfNeeded()

        let updatedWorkspace = workspace
            .merging(projects: graph.projectPaths)
            .adding(files: workspaceFiles)

        let workspacePath = try workspaceGenerator.generate(workspace: updatedWorkspace,
                                                            path: path,
                                                            graph: graph,
                                                            tuistConfig: tuistConfig)
        return (workspacePath, graph)
    }
}
