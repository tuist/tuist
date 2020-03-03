import Basic
import Foundation
import TuistCore
import TuistSupport
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
    /// Generates the given workspace.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - path: Path to the directory where the generation command is executed from.
    ///   - graph: In-memory representation of the graph.
    /// - Returns: Generated workspace descriptor
    /// - Throws: An error if the generation fails.
    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing) throws -> GeneratedWorkspaceDescriptor
}

final class WorkspaceGenerator: WorkspaceGenerating {
    // MARK: - Attributes

    private let projectGenerator: ProjectGenerating
    private let workspaceStructureGenerator: WorkspaceStructureGenerating
    private let schemesGenerator: SchemesGenerating

    // MARK: - Init

    convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator)
        self.init(projectGenerator: projectGenerator,
                  workspaceStructureGenerator: WorkspaceStructureGenerator(),
                  schemesGenerator: SchemesGenerator())
    }

    init(projectGenerator: ProjectGenerating,
         workspaceStructureGenerator: WorkspaceStructureGenerating,
         schemesGenerator: SchemesGenerating) {
        self.projectGenerator = projectGenerator
        self.workspaceStructureGenerator = workspaceStructureGenerator
        self.schemesGenerator = schemesGenerator
    }

    // MARK: - WorkspaceGenerating

    func generate(workspace: Workspace, path: AbsolutePath, graph: Graphing) throws -> GeneratedWorkspaceDescriptor {
        let workspaceName = "\(graph.name).xcworkspace"

        Printer.shared.print(section: "Generating workspace \(workspaceName)")

        /// Projects
        let projects = try graph.projects.map { project in
            try projectGenerator.generate(project: project,
                                          graph: graph,
                                          sourceRootPath: project.path,
                                          xcodeprojPath: nil)
        }

        let generatedProjects: [AbsolutePath: GeneratedProject] = Dictionary(uniqueKeysWithValues: projects.map { project in
            let pbxproj = project.xcodeProj.pbxproj
            let targets = pbxproj.nativeTargets.map {
                ($0.name, $0)
            }
            return (project.path.parentDirectory, // TODO: distinguish between XcodeProj path and Project path
                    GeneratedProject(pbxproj: pbxproj,
                                     path: project.path,
                                     targets: Dictionary(targets, uniquingKeysWith: { $1 }),
                                     name: project.path.basename))
        })

        // Workspace structure
        let structure = workspaceStructureGenerator.generateStructure(path: path,
                                                                      workspace: workspace,
                                                                      fileHandler: FileHandler.shared)

        let workspacePath = path.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let xcWorkspace = XCWorkspace(data: workspaceData)
        try workspaceData.children = structure.contents.map {
            try recursiveChildElement(generatedProjects: generatedProjects,
                                      element: $0,
                                      path: path)
        }

        // Schemes

        let schemes = try schemesGenerator.generateWorkspaceSchemesDescriptors(workspace: workspace,
                                                                               xcworkspacePath: workspacePath,
                                                                               generatedProjects: generatedProjects,
                                                                               graph: graph)

        return GeneratedWorkspaceDescriptor(path: workspacePath,
                                            xcworkspace: xcWorkspace,
                                            projects: projects,
                                            schemes: schemes,
                                            sideEffects: [])
    }

    private func write(workspace _: Workspace,
                       xcworkspace: XCWorkspace,
                       generatedProjects _: [AbsolutePath: GeneratedProject],
                       graph _: Graphing,
                       to: AbsolutePath) throws {
        let workspaceDataFile = "contents.xcworkspacedata"
        let fileHandler = FileHandler.shared

        // If the workspace doesn't exist we can write it because there isn't any
        // Xcode instance that might depend on it.
        if !fileHandler.exists(to.appending(component: workspaceDataFile)) {
            try xcworkspace.write(path: to.path)
            return
        }

        // If the workspace exists, we want to reduce the likeliness of causing
        // Xcode not to be able to reload the workspace.
        // We only replace the current one if something has changed.
        try fileHandler.inTemporaryDirectory { temporaryPath in
            let temporaryPath = temporaryPath.appending(component: to.basename)
            try xcworkspace.write(path: temporaryPath.path)

            let workspaceData: (AbsolutePath) throws -> Data = {
                let dataPath = $0.appending(component: workspaceDataFile)
                return try Data(contentsOf: dataPath.url)
            }

            let currentData = try workspaceData(to)
            let currentWorkspaceData = try workspaceData(temporaryPath)

            guard currentData != currentWorkspaceData else {
                return
            }

            try fileHandler.createFolder(to)
            try fileHandler.replace(to.appending(component: workspaceDataFile),
                                    with: temporaryPath.appending(component: workspaceDataFile))
        }
    }

    private func writeSchemes(workspace: Workspace,
                              xcworkspace _: XCWorkspace,
                              generatedProjects: [AbsolutePath: GeneratedProject],
                              graph: Graphing,
                              to path: AbsolutePath) throws {
        try schemesGenerator.wipeSchemes(at: path)
        try schemesGenerator.generateWorkspaceSchemes(workspace: workspace,
                                                      xcworkspacePath: path,
                                                      generatedProjects: generatedProjects,
                                                      graph: graph)
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
