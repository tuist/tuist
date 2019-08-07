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
    /// Generates the given workspace.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - path: Path to the directory where the generation command is executed from.
    ///   - graph: In-memory representation of the graph.
    ///   - tuistConfig: Tuist configuration
    /// - Returns: Path to the generated workspace.
    /// - Throws: An error if the generation fails.
    @discardableResult
    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing,
                  tuistConfig: TuistConfig) throws -> AbsolutePath
}

final class WorkspaceGenerator: WorkspaceGenerating {
    // MARK: - Attributes

    private let projectGenerator: ProjectGenerating
    private let system: Systeming
    private let workspaceStructureGenerator: WorkspaceStructureGenerating

    /// Instance to generate the projects that compile the manifest files.
    private let derivedManifestProjectGenerator: DerivedManifestProjectGenerating

    // MARK: - Init

    convenience init() {
        let system = System()
        let defaultSettingsProvider = DefaultSettingsProvider()
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let derivedManifestProjectGenerator = DerivedManifestProjectGenerator()
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator,
                                                system: system)
        let cocoapodsInteractor = CocoaPodsInteractor()

        self.init(system: system,
                  projectGenerator: projectGenerator,
                  workspaceStructureGenerator: WorkspaceStructureGenerator(),
                  cocoapodsInteractor: cocoapodsInteractor,
                  derivedManifestProjectGenerator: derivedManifestProjectGenerator)
    }

    init(system: Systeming,
         projectGenerator: ProjectGenerating,
         workspaceStructureGenerator: WorkspaceStructureGenerating,
         cocoapodsInteractor: CocoaPodsInteracting,
         derivedManifestProjectGenerator: DerivedManifestProjectGenerating) {
        self.system = system
        self.projectGenerator = projectGenerator
        self.workspaceStructureGenerator = workspaceStructureGenerator
        self.cocoapodsInteractor = cocoapodsInteractor
        self.derivedManifestProjectGenerator = derivedManifestProjectGenerator
    }

    // MARK: - WorkspaceGenerating

    /// Generates the given workspace.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    ///   - path: Path to the directory where the generation command is executed from.
    ///   - graph: In-memory representation of the graph.
    ///   - tuistConfig: Tuist configuration.
    /// - Returns: Path to the generated workspace.
    /// - Throws: An error if the generation fails.
    @discardableResult
    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing,
                  tuistConfig: TuistConfig) throws -> AbsolutePath {
        let workspaceName = "\(graph.name).xcworkspace"
        Printer.shared.print(section: "Generating workspace \(workspaceName)")

        /// Projects

        var generatedProjects = [AbsolutePath: GeneratedProject]()
        var manifestProjectPaths = [AbsolutePath]()

        try graph.projects.forEach { project in
            let generatedProject = try projectGenerator.generate(project: project,
                                                                 graph: graph,
                                                                 sourceRootPath: project.path)

            // Manifest project
            if tuistConfig.generationOptions.contains(.generateManifest) {
                let manifestProjectPath = try derivedManifestProjectGenerator.generate(project: project,
                                                                                       sourceRootPath: project.path)
                manifestProjectPaths.append(manifestProjectPath)
            }

            generatedProjects[project.path] = generatedProject
        }

        // Workspace structure
        let structure = workspaceStructureGenerator.generateStructure(path: path,
                                                                      workspace: workspace,
                                                                      manifestProjectPaths: manifestProjectPaths)

        let workspacePath = path.appending(component: workspaceName)
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
        if !FileHandler.shared.exists(to.appending(component: "contents.xcworkspacedata")) {
            try xcworkspace.write(path: to.path)
            return
        }

        // If the workspace exists, we want to reduce the likeliness of causing
        // Xcode not to be able to reload the workspace.
        // We only replace the current one if something has changed.
        try FileHandler.shared.inTemporaryDirectory { temporaryPath in
            try xcworkspace.write(path: temporaryPath.path)

            let workspaceData: (AbsolutePath) throws -> Data = {
                let dataPath = $0.appending(component: "contents.xcworkspacedata")
                return try Data(contentsOf: dataPath.url)
            }

            let currentData = try workspaceData(to)
            let currentWorkspaceData = try workspaceData(temporaryPath)

            if currentData != currentWorkspaceData {
                try FileHandler.shared.replace(to, with: temporaryPath)
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
            let location: XCWorkspaceDataElementLocationType!
            if let path = groupPath?.relative(to: path).pathString {
                location = XCWorkspaceDataElementLocationType.group(path)
            } else {
                location = XCWorkspaceDataElementLocationType.group("container:")
            }

            let groupReference = XCWorkspaceDataGroup(
                location: location,
                name: name,
                children: try contents.map {
                    try recursiveChildElement(generatedProjects: generatedProjects,
                                              element: $0,
                                              path: path)
                }.sorted(by: workspaceDataElementSort)
            )

            return .group(groupReference)

        case let .project(path: projectPath):
            if !fileHandler.exists(projectPath) {
                throw WorkspaceGeneratorError.projectNotFound(path: projectPath)
            }
            return workspaceFileElement(path: projectPath.relative(to: path))
        }
    }
}
