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
    ///   - destinationDirectory: Directory in which the Xcode project will be generated.
    ///   - onlyCurrentDirectory: True if only the manifest in the current directory should be included.
    ///   - plugins: The plugins to load as part of the edit project.
    /// - Returns: The path to the generated Xcode project.
    func edit(
        at editingPath: AbsolutePath,
        in destinationDirectory: AbsolutePath,
        onlyCurrentDirectory: Bool,
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

    /// Utility to locate the resource synthesizers directory
    let resourceSynthesizersDirectoryLocator: ResourceSynthesizerPathLocating

    /// Utility to locate the stencil directory
    let stencilDirectoryLocator: StencilPathLocating

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
        resourceSynthesizersDirectoryLocator: ResourceSynthesizerPathLocating = ResourceSynthesizerPathLocator(),
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring = CacheDirectoriesProviderFactory(),
        stencilDirectoryLocator: StencilPathLocating = StencilPathLocator(),
        projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring =
            ProjectDescriptionHelpersBuilderFactory()
    ) {
        self.generator = generator
        self.projectEditorMapper = projectEditorMapper
        self.resourceLocator = resourceLocator
        self.manifestFilesLocator = manifestFilesLocator
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.writer = writer
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.resourceSynthesizersDirectoryLocator = resourceSynthesizersDirectoryLocator
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.stencilDirectoryLocator = stencilDirectoryLocator
        self.projectDescriptionHelpersBuilderFactory = projectDescriptionHelpersBuilderFactory
    }

    // swiftlint:disable:next function_body_length
    func edit(
        at editingPath: AbsolutePath,
        in destinationDirectory: AbsolutePath,
        onlyCurrentDirectory: Bool,
        plugins: Plugins
    ) throws -> AbsolutePath {
        let tuistIgnoreContent = (try? FileHandler.shared.readTextFile(editingPath.appending(component: ".tuistignore"))) ?? ""
        let tuistIgnoreEntries = tuistIgnoreContent
            .split(separator: "\n")
            .map(String.init)
            .map { entry -> String in
                guard !entry.starts(with: "**") else { return entry }
                let path = editingPath.appending(RelativePath(entry))
                if FileHandler.shared.isFolder(path) {
                    return path.appending(component: "**").pathString
                } else {
                    return path.pathString
                }
            }

        let pathsToExclude = [
            "**/\(Constants.tuistDirectoryName)/\(Constants.DependenciesDirectory.name)/**",
            "**/\(Constants.DependenciesDirectory.packageBuildDirectoryName)/**",
        ] + tuistIgnoreEntries

        let projectDescriptionPath = try resourceLocator.projectDescription()
        let projectManifests = manifestFilesLocator.locateProjectManifests(
            at: editingPath,
            excluding: pathsToExclude,
            onlyCurrentDirectory: onlyCurrentDirectory
        )
        let configPath = manifestFilesLocator.locateConfig(at: editingPath)
        let cacheDirectory = try cacheDirectoryProviderFactory.cacheDirectories(config: nil)
        let projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilderFactory.projectDescriptionHelpersBuilder(
            cacheDirectory: cacheDirectory.cacheDirectory(for: .projectDescriptionHelpers)
        )
        let dependenciesPath = manifestFilesLocator.locateDependencies(at: editingPath)

        let helpers = helpersDirectoryLocator.locate(at: editingPath).map {
            [
                FileHandler.shared.glob($0, glob: "**/*.swift"),
                FileHandler.shared.glob($0, glob: "**/*.docc"),
            ].flatMap { $0 }
        } ?? []

        let templates = templatesDirectoryLocator.locateUserTemplates(at: editingPath).map {
            FileHandler.shared.glob($0, glob: "**/*.swift") + FileHandler.shared.glob($0, glob: "**/*.stencil")
        } ?? []

        let resourceSynthesizers = resourceSynthesizersDirectoryLocator.locate(at: editingPath).map {
            FileHandler.shared.glob($0, glob: "**/*.stencil")
        } ?? []

        let stencils = stencilDirectoryLocator.locate(at: editingPath).map {
            FileHandler.shared.glob($0, glob: "**/*.stencil")
        } ?? []

        let editablePluginManifests = locateEditablePluginManifests(
            at: editingPath,
            excluding: pathsToExclude,
            plugins: plugins,
            onlyCurrentDirectory: onlyCurrentDirectory
        )
        let builtPluginHelperModules = try buildRemotePluginModules(
            in: editingPath,
            projectDescriptionPath: projectDescriptionPath,
            plugins: plugins,
            projectDescriptionHelpersBuilder: projectDescriptionHelpersBuilder
        )

        /// We error if the user tries to edit a project in a directory where there are no editable files.
        if projectManifests.isEmpty, editablePluginManifests.isEmpty, helpers.isEmpty, templates.isEmpty,
           resourceSynthesizers.isEmpty, stencils.isEmpty
        {
            throw ProjectEditorError.noEditableFiles(editingPath)
        }

        // To be sure that we are using the same binary of Tuist that invoked `edit`
        let tuistPath = try AbsolutePath(validating: TuistCommand.processArguments()!.first!)
        let workspaceName = "Manifests"

        let graph = try projectEditorMapper.map(
            name: workspaceName,
            tuistPath: tuistPath,
            sourceRootPath: editingPath,
            destinationDirectory: destinationDirectory,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            projectManifests: projectManifests.map(\.path),
            editablePluginManifests: editablePluginManifests,
            pluginProjectDescriptionHelpersModule: builtPluginHelperModules,
            helpers: helpers,
            templates: templates,
            resourceSynthesizers: resourceSynthesizers,
            stencils: stencils,
            projectDescriptionSearchPath: projectDescriptionPath.parentDirectory
        )

        let graphTraverser = GraphTraverser(graph: graph)
        let descriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)
        try writer.write(workspace: descriptor)
        return descriptor.xcworkspacePath
    }

    /// - Returns: A list of plugin manifests which should be loaded as part of the project.
    private func locateEditablePluginManifests(
        at path: AbsolutePath,
        excluding: [String],
        plugins: Plugins,
        onlyCurrentDirectory: Bool
    ) -> [EditablePluginManifest] {
        let loadedEditablePluginManifests = plugins.projectDescriptionHelpers
            .filter { $0.location == .local }
            .map { EditablePluginManifest(name: $0.name, path: $0.path.parentDirectory) }

        let localEditablePluginManifests = manifestFilesLocator.locatePluginManifests(
            at: path,
            excluding: excluding,
            onlyCurrentDirectory: onlyCurrentDirectory
        )
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
