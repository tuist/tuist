import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistScaffold
import TuistSupport

enum ProjectEditorError: FatalError, Equatable {
    /// This error is thrown when we try to edit in a project in a directory that has no editable files.
    case noEditableFiles(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .noEditableFiles: return .abort
        }
    }

    var description: String {
        switch self {
        case let .noEditableFiles(path):
            return "There are no editable files at \(path.pathString)"
        }
    }
}

protocol ProjectEditing: AnyObject {
    /// Generates an Xcode project to edit the Project defined in the given directory.
    /// - Parameters:
    ///   - editingPath: Directory whose project will be edited.
    ///   - onlyCurrentDirectory: True if only the manifest in the current directory should be included.
    ///   - destinationDirectory: Directory in which the Xcode project will be generated.
    ///   - plugins: The plugins to load as part of the edit project.
    /// - Returns: The path to the generated Xcode project.
    func edit(
        at editingPath: AbsolutePath,
        in destinationDirectory: AbsolutePath,
        plugins: Plugins
    ) throws -> AbsolutePath
}

final class ProjectEditor: ProjectEditing {
    /// Project generator.
    let generator: DescriptorGenerating

    /// Project editor mapper.
    let projectEditorMapper: ProjectEditorMapping

    /// Utility to locate Tuist's resources.
    let resourceLocator: ResourceLocating

    /// Utility to locate manifest files.
    let manifestFilesLocator: ManifestFilesLocating

    /// Utility to locate the helpers directory.
    let helpersDirectoryLocator: HelpersDirectoryLocating

    /// Utility to locate the custom templates directory
    let templatesDirectoryLocator: TemplatesDirectoryLocating

    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring

    private let projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring

    /// Xcode Project writer
    private let writer: XcodeProjWriting

    init(
        generator: DescriptorGenerating = DescriptorGenerator(),
        projectEditorMapper: ProjectEditorMapping = ProjectEditorMapper(),
        resourceLocator: ResourceLocating = ResourceLocator(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator(),
        writer: XcodeProjWriting = XcodeProjWriter(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory(),
        projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring = ProjectDescriptionHelpersBuilderFactory()
    ) {
        self.generator = generator
        self.projectEditorMapper = projectEditorMapper
        self.resourceLocator = resourceLocator
        self.manifestFilesLocator = manifestFilesLocator
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.writer = writer
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.projectDescriptionHelpersBuilderFactory = projectDescriptionHelpersBuilderFactory
    }

    func edit(
        at editingPath: AbsolutePath,
        in destinationDirectory: AbsolutePath,
        plugins: Plugins
    ) throws -> AbsolutePath {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let projectManifests = manifestFilesLocator.locateProjectManifests(at: editingPath)
        let configPath = manifestFilesLocator.locateConfig(at: editingPath)
        let cacheDirectory = try cacheDirectoryProviderFactory.cacheDirectories(config: nil)
        let projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilderFactory.projectDescriptionHelpersBuilder(
            cacheDirectory: cacheDirectory.projectDescriptionHelpersCacheDirectory)
        let dependenciesPath = manifestFilesLocator.locateDependencies(at: editingPath)
        let setupPath = manifestFilesLocator.locateSetup(at: editingPath)

        let helpers = helpersDirectoryLocator.locate(at: editingPath).map {
            FileHandler.shared.glob($0, glob: "**/*.swift")
        } ?? []

        let templates = templatesDirectoryLocator.locateUserTemplates(at: editingPath).map {
            FileHandler.shared.glob($0, glob: "**/*.swift") + FileHandler.shared.glob($0, glob: "**/*.stencil")
        } ?? []

        let editablePluginManifests = locateEditablePluginManifests(at: editingPath, plugins: plugins)
        let builtPluginHelperModules = try buildRemotePluginModules(
            in: editingPath,
            projectDescriptionPath: projectDescriptionPath,
            plugins: plugins,
            projectDescriptionHelpersBuilder: projectDescriptionHelpersBuilder
        )

        /// We error if the user tries to edit a project in a directory where there are no editable files.
        if projectManifests.isEmpty, editablePluginManifests.isEmpty, helpers.isEmpty, templates.isEmpty {
            throw ProjectEditorError.noEditableFiles(editingPath)
        }

        // To be sure that we are using the same binary of Tuist that invoked `edit`
        let tuistPath = AbsolutePath(TuistCommand.processArguments()!.first!)
        let workspaceName = "Manifests"

        let graph = try projectEditorMapper.map(
            name: workspaceName,
            tuistPath: tuistPath,
            sourceRootPath: editingPath,
            destinationDirectory: destinationDirectory,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifests.map(\.1),
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: builtPluginHelperModules,
            helpers: helpers,
            templates: templates,
            projectDescriptionPath: projectDescriptionPath
        )

        let graphTraverser = ValueGraphTraverser(graph: graph)
        let descriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)
        try writer.write(workspace: descriptor)
        return descriptor.xcworkspacePath
    }

    /// - Returns: A list of plugin manifests which should be loaded as part of the project.
    private func locateEditablePluginManifests(at path: AbsolutePath, plugins: Plugins) -> [EditablePluginManifest] {
        let loadedEditablePluginManifests = plugins.projectDescriptionHelpers
            .filter { $0.location == .local }
            .map { EditablePluginManifest(name: $0.name, path: $0.path.parentDirectory) }

        let localEditablePluginManifests = manifestFilesLocator.locatePluginManifests(at: path)
            .map { EditablePluginManifest(name: $0.parentDirectory.basename, path: $0.parentDirectory) }

        return Array(Set(loadedEditablePluginManifests + localEditablePluginManifests))
    }

    /// - Returns: Builds all remote plugins and returns a list of the helper modules.
    private func buildRemotePluginModules(
        in path: AbsolutePath,
        projectDescriptionPath: AbsolutePath,
        plugins: Plugins,
        projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    ) throws -> [ProjectDescriptionHelpersModule] {
        let loadedPluginHelpers = plugins.projectDescriptionHelpers.filter { $0.location == .remote }
        return try projectDescriptionHelpersBuilder.buildPlugins(
            at: path,
            projectDescriptionSearchPaths: ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath),
            projectDescriptionHelperPlugins: loadedPluginHelpers
        )
    }
}
