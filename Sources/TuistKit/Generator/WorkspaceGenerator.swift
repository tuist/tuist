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
    let projectDirectoryHelper: ProjectDirectoryHelping
    let fileHandler: FileHandling

    // MARK: - Init

    convenience init(system: Systeming = System(),
                     printer: Printing = Printer(),
                     projectDirectoryHelper: ProjectDirectoryHelping = ProjectDirectoryHelper(),
                     fileHandler: FileHandling = FileHandler()) {
        self.init(system: system,
                  printer: printer,
                  projectDirectoryHelper: projectDirectoryHelper,
                  projectGenerator: ProjectGenerator(printer: printer,
                                                     system: system),
                  fileHandler: fileHandler)
    }

    init(system: Systeming,
         printer: Printing,
         projectDirectoryHelper: ProjectDirectoryHelping,
         projectGenerator: ProjectGenerating,
         fileHandler: FileHandling) {
        self.system = system
        self.printer = printer
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

        /// Manifests

        let manifestFiles: [XCWorkspaceDataElement] = [Manifest.workspace, Manifest.setup]
            .lazy
            .map(pipe(get(\.fileName), path.appending))
            .filter(fileHandler.exists)
            .map { $0.relative(to: path) }
            .map(workspaceFileElement)

        workspace.data.children.append(contentsOf: manifestFiles)

        /// Projects
        var workspaceElements = [XCWorkspaceDataElement]()

        try graph.projects.forEach { project in
            let sourceRootPath = try projectDirectoryHelper.setupProjectDirectory(project: project,
                                                                                  directory: directory)
            let generatedProject = try projectGenerator.generate(project: project,
                                                                 options: options,
                                                                 graph: graph,
                                                                 sourceRootPath: sourceRootPath)

            let relativePath = generatedProject.path.relative(to: path)
            workspaceElements.append(workspaceFileElement(path: relativePath))
        }
        workspaceData.children.append(contentsOf: workspaceElements.sorted(by: workspaceDataElementSort))

        try write(xcworkspace: workspace, to: workspacePath)

        return workspacePath
    }

    private func write(xcworkspace: XCWorkspace, to: AbsolutePath) throws {
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
}
