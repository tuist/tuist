import Basic
import Foundation
import TuistGenerator
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
    ///   - at: Directory whose project will be edited.
    ///   - destinationDirectory: Directory in which the Xcode project will be generated.
    /// - Returns: The path to the generated Xcode project.
    func edit(at: AbsolutePath, in destinationDirectory: AbsolutePath) throws -> AbsolutePath
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

    /// Utiltity to locate the custom templates directory
    let templatesDirectoryLocator: TemplatesDirectoryLocating

    /// Utility to fetch the versions of the system pieces that Tuist interacts with.
    let versionsFetcher: VersionsFetching

    /// Xcode Project writer
    private let writer: XcodeProjWriting

    init(generator: DescriptorGenerating = DescriptorGenerator(),
         projectEditorMapper: ProjectEditorMapping = ProjectEditorMapper(),
         resourceLocator: ResourceLocating = ResourceLocator(),
         manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
         helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator(),
         writer: XcodeProjWriting = XcodeProjWriter(),
         templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
         versionsFetcher: VersionsFetching = VersionsFetcher()) {
        self.generator = generator
        self.projectEditorMapper = projectEditorMapper
        self.resourceLocator = resourceLocator
        self.manifestFilesLocator = manifestFilesLocator
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.writer = writer
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.versionsFetcher = versionsFetcher
    }

    func edit(at: AbsolutePath, in dstDirectory: AbsolutePath) throws -> AbsolutePath {
        let xcodeprojPath = dstDirectory.appending(component: "Manifests.xcodeproj")
        let versions = try versionsFetcher.fetch()

        let projectDesciptionPath = try resourceLocator.projectDescription()
        let manifests = manifestFilesLocator.locate(at: at)
        var helpers: [AbsolutePath] = []
        if let helpersDirectory = helpersDirectoryLocator.locate(at: at) {
            helpers = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        }
        var templates: [AbsolutePath] = []
        if let templatesDirectory = templatesDirectoryLocator.locateUserTemplates(at: at) {
            templates = FileHandler.shared.glob(templatesDirectory, glob: "**/*.swift")
                + FileHandler.shared.glob(templatesDirectory, glob: "**/*.stencil")
        }

        /// We error if the user tries to edit a project in a directory where there are no editable files.
        if manifests.isEmpty, helpers.isEmpty, templates.isEmpty {
            throw ProjectEditorError.noEditableFiles(at)
        }

        // To be sure that we are using the same binary of Tuist that invoked `edit`
        let tuistPath = AbsolutePath(CommandRegistry.processArguments().first!)

        let (project, graph) = projectEditorMapper.map(tuistPath: tuistPath,
                                                       sourceRootPath: at,
                                                       manifests: manifests.map { $0.1 },
                                                       helpers: helpers,
                                                       templates: templates,
                                                       projectDescriptionPath: projectDesciptionPath,
                                                       versions: versions)

        let config = ProjectGenerationConfig(sourceRootPath: project.path,
                                             xcodeprojPath: xcodeprojPath)
        let descriptor = try generator.generateProject(project: project,
                                                       graph: graph,
                                                       config: config,
                                                       versions: versions)
        try writer.write(project: descriptor)
        return descriptor.xcodeprojPath
    }
}
