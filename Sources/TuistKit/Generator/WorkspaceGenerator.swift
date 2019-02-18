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
        
        /*-----------------------------------------------------------------------------------------
         // MARK: - Manifest Group
         -----------------------------------------------------------------------------------------*/

        let manifestFiles: [XCWorkspaceDataElement] = [ Manifest.workspace, Manifest.setup ]
            .lazy
            .map(\.fileName |> path.appending(component:))
            .filter(fileHandler.exists)
            .map(\.workspaceFileElement)

        workspace.data.children.append(contentsOf: manifestFiles)
        
        /*-----------------------------------------------------------------------------------------
         // MARK: - Projects
         -----------------------------------------------------------------------------------------*/
        
        try graph.projects.forEach { project in
            let sourceRootPath = try projectDirectoryHelper.setupProjectDirectory(project: project,
                                                                                  directory: directory)
            let generatedProject = try projectGenerator.generate(project: project,
                                                                 options: options,
                                                                 graph: graph,
                                                                 sourceRootPath: sourceRootPath)
            
            let relativePath = generatedProject.path.relative(to: path)
            workspace.data.children.append(relativePath.workspaceFileElement)
        }
        
        try workspace.write(path: workspacePath.path, override: true)

        return workspacePath
    }
    
}

/*-----------------------------------------------------------------------------------------
 // MARK: - Helper for generating XCWorkspaceDataElement from AbsolutePath and RelativePath
 -----------------------------------------------------------------------------------------*/

private protocol WorkspaceFileElement {
    var asString: String { get }
}

extension WorkspaceFileElement {
    
    var workspaceFileElement: XCWorkspaceDataElement {
        let location = XCWorkspaceDataElementLocationType.group(asString)
        let fileRef = XCWorkspaceDataFileRef(location: location)
        return .file(fileRef)
    }
    
}

extension AbsolutePath: WorkspaceFileElement { }
extension RelativePath: WorkspaceFileElement { }
