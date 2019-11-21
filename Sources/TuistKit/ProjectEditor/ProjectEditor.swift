import Basic
import Foundation
import TuistGenerator
import TuistSupport

protocol ProjectEditing: AnyObject {
    func edit(at: AbsolutePath, in destinationDirectory: AbsolutePath) throws
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

    init(generator: Generating = Generator(),
         projectEditorMapper: ProjectEditorMapping = ProjectEditorMapper(),
         resourceLocator: ResourceLocating = ResourceLocator(),
         manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
         helpersDirectoryLocator: HelpersDirectoryLocating = HelpersDirectoryLocator()) {
        self.generator = generator
        self.projectEditorMapper = projectEditorMapper
        self.resourceLocator = resourceLocator
        self.manifestFilesLocator = manifestFilesLocator
        self.helpersDirectoryLocator = helpersDirectoryLocator
    }

    func edit(at: AbsolutePath, in destinationDirectory: AbsolutePath) throws {
        let projectDesciptionPath = try resourceLocator.projectDescription()
        let manifests = manifestFilesLocator.locate(at: at)
        var helpers: [AbsolutePath] = []
        if let helpersDirectory = self.helpersDirectoryLocator.locate(at: at) {
            helpers = FileHandler.shared.glob(helpersDirectory, glob: "**/*.swift")
        }

        let (project, graph) = projectEditorMapper.map(sourceRootPath: destinationDirectory,
                                                       manifests: manifests.map { $0.1 },
                                                       helpers: helpers,
                                                       projectDescriptionPath: projectDesciptionPath)
        _ = try generator.generateProject(project, graph: graph)
    }
}
