import Basic
import Foundation
import TuistGenerator
import TuistLoader
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
    let generator: Generating

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

    init(generator: Generating = Generator(),
         projectEditorMapper: ProjectEditorMapping = ProjectEditorMapper(),
         resourceLocator: ResourceLocating = ResourceLocator(),
         manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
         helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator(),
         templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator()) {
        self.generator = generator
        self.projectEditorMapper = projectEditorMapper
        self.resourceLocator = resourceLocator
        self.manifestFilesLocator = manifestFilesLocator
        self.helpersDirectoryLocator = helpersDirectoryLocator
        self.templatesDirectoryLocator = templatesDirectoryLocator
    }

    func edit(at: AbsolutePath, in dstDirectory: AbsolutePath) throws -> AbsolutePath {
        let xcodeprojPath = dstDirectory.appending(component: "Manifests.xcodeproj")

        let projectDesciptionPath = try resourceLocator.projectDescription()
        let manifests = manifestFilesLocator.locate(at: at)
        var helpers: [AbsolutePath] = []
        if let helpersDirectory = helpersDirectoryLocator.locate(at: at) {
            helpers = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        }
        var templates: [AbsolutePath] = []
        if let templatesDirectory = templatesDirectoryLocator.locateCustom(at: at) {
            // Add only Template manifests
            templates = FileHandler.shared.glob(templatesDirectory, glob: "**/*.swift")
        }

        /// We error if the user tries to edit a project in a directory where there are no editable files.
        if manifests.isEmpty, helpers.isEmpty, templates.isEmpty {
            throw ProjectEditorError.noEditableFiles(at)
        }

        let (project, graph) = projectEditorMapper.map(sourceRootPath: at,
                                                       manifests: manifests.map { $0.1 },
                                                       helpers: helpers,
                                                       templates: templates,
                                                       projectDescriptionPath: projectDesciptionPath)
        return try generator.generateProject(project,
                                             graph: graph,
                                             sourceRootPath: project.path,
                                             xcodeprojPath: xcodeprojPath)
    }
}
