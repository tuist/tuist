import Basic
import Foundation
import TuistCore
import xcodeproj

protocol WorkspaceGenerating: AnyObject {
    @discardableResult
    func generate(path: AbsolutePath, graph: Graphing, options: GenerationOptions, directory: GenerationDirectory) throws -> AbsolutePath
}

final class WorkspaceGenerator: WorkspaceGenerating {
    // MARK: - Attributes

    let projectGenerator: ProjectGenerating
    let system: Systeming
    let printer: Printing
    let resourceLocator: ResourceLocating
    let projectDirectoryHelper: ProjectDirectoryHelping
    let fileHandler: FileHandling

    // MARK: - Init

    convenience init(system: Systeming = System(),
                     printer: Printing = Printer(),
                     resourceLocator: ResourceLocating = ResourceLocator(),
                     projectDirectoryHelper: ProjectDirectoryHelping = ProjectDirectoryHelper(),
                     fileHandler: FileHandling = FileHandler()) {
        self.init(system: system,
                  printer: printer,
                  resourceLocator: resourceLocator,
                  projectDirectoryHelper: projectDirectoryHelper,
                  projectGenerator: ProjectGenerator(printer: printer,
                                                     system: system,
                                                     resourceLocator: resourceLocator),
                  fileHandler: fileHandler)
    }

    init(system: Systeming,
         printer: Printing,
         resourceLocator: ResourceLocating,
         projectDirectoryHelper: ProjectDirectoryHelping,
         projectGenerator: ProjectGenerating,
         fileHandler: FileHandling) {
        self.system = system
        self.printer = printer
        self.resourceLocator = resourceLocator
        self.projectDirectoryHelper = projectDirectoryHelper
        self.projectGenerator = projectGenerator
        self.fileHandler = fileHandler
    }

    // MARK: - WorkspaceGenerating

    @discardableResult
    func generate(path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  directory: GenerationDirectory = .manifest) throws -> AbsolutePath {
        let workspaceRootPath = try projectDirectoryHelper.setupDirectory(name: graph.name,
                                                                          path: graph.entryPath,
                                                                          directory: directory)
        let workspaceName = "\(graph.name).xcworkspace"
        printer.print(section: "Generating workspace \(workspaceName)")
        let workspacePath = workspaceRootPath.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)

        // MARK: - Manifests

        let manifestFiles: [XCWorkspaceDataElement] = [Manifest.workspace, Manifest.setup]
            .lazy
            .map(pipe(get(\.fileName), path.appending))
            .filter(fileHandler.exists)
            .map { $0.relative(to: path) }
            .map(workspaceFileElement)

        workspace.data.children.append(contentsOf: manifestFiles)

        // MARK: - Projects

        try graph.projects.forEach { project in
            let sourceRootPath = try projectDirectoryHelper.setupProjectDirectory(project: project,
                                                                                  directory: directory)
            let generatedProject = try projectGenerator.generate(project: project,
                                                                 options: options,
                                                                 graph: graph,
                                                                 sourceRootPath: sourceRootPath)

            let relativePath = generatedProject.path.relative(to: path)
            workspace.data.children.append(workspaceFileElement(path: relativePath))
        }

        try write(xcworkspace: workspace, to: workspacePath)

        return workspacePath
    }

    fileprivate func write(xcworkspace: XCWorkspace, to: AbsolutePath) throws {
        // If the workspace doesn't exist we can write it because there isn't any
        // Xcode instance that might depend on it.
        if !fileHandler.exists(to) {
            try xcworkspace.write(path: to.path)
            return
        }

        // If the workspace exists, we want to reduce the likeliness of causing
        // Xcode not to be able to reload the workspace.
        // We only replace the current one if something has changed.
        try fileHandler.inTemporaryDirectory { temporaryPath in
            try xcworkspace.write(path: temporaryPath.path)

            let workspaceData: (AbsolutePath) throws -> Data = {
                let dataPath = $0.appending(component: "contents.xcworkspacedata")
                return try Data(contentsOf: dataPath.url)
            }

            let currentData = try workspaceData(to)
            let currentWorkspaceData = try workspaceData(temporaryPath)

            if currentData != currentWorkspaceData {
                try fileHandler.replace(to, with: temporaryPath)
            }
        }
    }

    /// Create a XCWorkspaceDataElement.file from a path string.
    ///
    /// - Parameter path: The relative path to the file
    fileprivate func workspaceFileElement(path: RelativePath) -> XCWorkspaceDataElement {
        let location = XCWorkspaceDataElementLocationType.group(path.asString)
        let fileRef = XCWorkspaceDataFileRef(location: location)
        return .file(fileRef)
    }
}
