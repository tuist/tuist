import Basic
import Foundation
import TuistCore
import XcodeProj

enum WorkspaceGeneratorError: FatalError {
    case projectNotFound(path: AbsolutePath)
    var type: ErrorType {
        switch self {
        case .projectNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .projectNotFound(path: path):
            return "Project not found at path: \(path)"
        }
    }
}

protocol WorkspaceGenerating: AnyObject {
    @discardableResult
    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  directory: GenerationDirectory) throws -> AbsolutePath
}

final class WorkspaceGenerator: WorkspaceGenerating {
    // MARK: - Attributes

    private let projectGenerator: ProjectGenerating
    private let system: Systeming
    private let printer: Printing
    private let projectDirectoryHelper: ProjectDirectoryHelping
    private let fileHandler: FileHandling
    private let workspaceStructureGenerator: WorkspaceStructureGenerating

    // MARK: - Init

    convenience init(system: Systeming = System(),
                     printer: Printing = Printer(),
                     projectDirectoryHelper: ProjectDirectoryHelping = ProjectDirectoryHelper(),
                     fileHandler: FileHandling = FileHandler(),
                     defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator,
                                                printer: printer,
                                                system: system,
                                                fileHandler: fileHandler)
        self.init(system: system,
                  printer: printer,
                  projectDirectoryHelper: projectDirectoryHelper,
                  projectGenerator: projectGenerator,
                  fileHandler: fileHandler,
                  workspaceStructureGenerator: WorkspaceStructureGenerator(fileHandler: fileHandler))
    }

    init(system: Systeming,
         printer: Printing,
         projectDirectoryHelper: ProjectDirectoryHelping,
         projectGenerator: ProjectGenerating,
         fileHandler: FileHandling,
         workspaceStructureGenerator: WorkspaceStructureGenerating) {
        self.system = system
        self.printer = printer
        self.projectDirectoryHelper = projectDirectoryHelper
        self.projectGenerator = projectGenerator
        self.fileHandler = fileHandler
        self.workspaceStructureGenerator = workspaceStructureGenerator
    }

    // MARK: - WorkspaceGenerating

    @discardableResult
    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  directory: GenerationDirectory = .manifest) throws -> AbsolutePath {
        let workspaceRootPath = try projectDirectoryHelper.setupDirectory(name: graph.name,
                                                                          path: graph.entryPath,
                                                                          directory: directory)
        let workspaceName = "\(graph.name).xcworkspace"
        printer.print(section: "Generating workspace \(workspaceName)")

        /// Projects

        var generatedProjects = [AbsolutePath: GeneratedProject]()
        try graph.projects.forEach { project in
            let sourceRootPath = try projectDirectoryHelper.setupProjectDirectory(project: project,
                                                                                  directory: directory)
            let generatedProject = try projectGenerator.generate(project: project,
                                                                 options: options,
                                                                 graph: graph,
                                                                 sourceRootPath: sourceRootPath)

            generatedProjects[project.path] = generatedProject
        }

        // Workspace structure

        let structure = workspaceStructureGenerator.generateStructure(path: path,
                                                                      workspace: workspace)

        let workspacePath = workspaceRootPath.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let xcWorkspace = XCWorkspace(data: workspaceData)
        try workspaceData.children = structure.contents.map {
            try recursiveChildElement(generatedProjects: generatedProjects,
                                      element: $0,
                                      path: path)
        }

        try write(xcworkspace: xcWorkspace, to: workspacePath)

        return workspacePath
    }

    private func write(xcworkspace: XCWorkspace, to: AbsolutePath) throws {
        // If the workspace doesn't exist we can write it because there isn't any
        // Xcode instance that might depend on it.
        if !fileHandler.exists(to.appending(component: "contents.xcworkspacedata")) {
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
    private func workspaceFileElement(path: RelativePath) -> XCWorkspaceDataElement {
        let location = XCWorkspaceDataElementLocationType.group(path.pathString)
        let fileRef = XCWorkspaceDataFileRef(location: location)
        return .file(fileRef)
    }

    /// Sorting function for workspace data elements. It applies the following sorting criteria:
    ///  - Files sorted before groups.
    ///  - Groups sorted by name.
    ///  - Files sorted using the workspaceFilePathSort sort function.
    ///
    /// - Parameters:
    ///   - lhs: First file to be sorted.
    ///   - rhs: Second file to be sorted.
    /// - Returns: True if the first workspace data element should be before the second one.
    private func workspaceDataElementSort(lhs: XCWorkspaceDataElement, rhs: XCWorkspaceDataElement) -> Bool {
        switch (lhs, rhs) {
        case let (.file(lhsFile), .file(rhsFile)):
            return workspaceFilePathSort(lhs: lhsFile.location.path,
                                         rhs: rhsFile.location.path)
        case let (.group(lhsGroup), .group(rhsGroup)):
            return lhsGroup.location.path < rhsGroup.location.path
        case (.file, .group):
            return true
        case (.group, .file):
            return false
        }
    }

    /// Sorting function for workspace data file elements. It applies the following sorting criteria:
    ///  - Xcode projects are sorted after other files.
    ///  - Xcode projects are sorted by name.
    ///  - Other files are sorted by name.
    ///
    /// - Parameters:
    ///   - lhs: First file path to be sorted.
    ///   - rhs: Second file path to be sorted.
    /// - Returns: True if the first element should be sorted before the second.
    private func workspaceFilePathSort(lhs: String, rhs: String) -> Bool {
        let lhsIsXcodeProject = lhs.hasSuffix(".xcodeproj")
        let rhsIsXcodeProject = rhs.hasSuffix(".xcodeproj")

        switch (lhsIsXcodeProject, rhsIsXcodeProject) {
        case (true, true):
            return lhs < rhs
        case (false, false):
            return lhs < rhs
        case (true, false):
            return false
        case (false, true):
            return true
        }
    }

    private func recursiveChildElement(generatedProjects: [AbsolutePath: GeneratedProject],
                                       element: WorkspaceStructure.Element,
                                       path: AbsolutePath) throws -> XCWorkspaceDataElement {
        switch element {
        case let .file(path: filePath):
            return workspaceFileElement(path: filePath.relative(to: path))

        case let .folderReference(path: folderPath):
            return workspaceFileElement(path: folderPath.relative(to: path))

        case let .group(name: name, path: groupPath, contents: contents):
            let location = XCWorkspaceDataElementLocationType.group(groupPath.relative(to: path).pathString)

            let groupReference = XCWorkspaceDataGroup(
                location: location,
                name: name,
                children: try contents.map {
                    try recursiveChildElement(generatedProjects: generatedProjects,
                                              element: $0,
                                              path: groupPath)
                }.sorted(by: workspaceDataElementSort)
            )

            return .group(groupReference)

        case let .project(path: projectPath):
            guard let generatedProject = generatedProjects[projectPath] else {
                throw WorkspaceGeneratorError.projectNotFound(path: projectPath)
            }
            let relativePath = generatedProject.path.relative(to: path)
            return workspaceFileElement(path: relativePath)
        }
    }
}
