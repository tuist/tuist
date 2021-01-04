import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XcodeProj

enum WorkspaceDescriptorGeneratorError: FatalError {
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

protocol WorkspaceDescriptorGenerating: AnyObject {
    /// Generates the given workspace.
    ///
    /// - Parameters:
    ///   - graphTraverser: Graph traverser.
    /// - Returns: Generated workspace descriptor
    /// - Throws: An error if the generation fails.
    func generate(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor
}

final class WorkspaceDescriptorGenerator: WorkspaceDescriptorGenerating {
    struct Config {
        /// The execution context to use when generating
        /// descriptors for each project within the workspace / graph
        var projectGenerationContext: ExecutionContext
        static var `default`: Config {
            Config(projectGenerationContext: .concurrent)
        }
    }

    // MARK: - Attributes

    private let projectDescriptorGenerator: ProjectDescriptorGenerating
    private let workspaceStructureGenerator: WorkspaceStructureGenerating
    private let schemeDescriptorsGenerator: SchemeDescriptorsGenerating
    private let config: Config

    // MARK: - Init

    convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider(),
                     config: Config = .default)
    {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectDescriptorGenerator = ProjectDescriptorGenerator(targetGenerator: targetGenerator,
                                                                    configGenerator: configGenerator)
        self.init(projectDescriptorGenerator: projectDescriptorGenerator,
                  workspaceStructureGenerator: WorkspaceStructureGenerator(),
                  schemeDescriptorsGenerator: SchemeDescriptorsGenerator(),
                  config: config)
    }

    init(projectDescriptorGenerator: ProjectDescriptorGenerating,
         workspaceStructureGenerator: WorkspaceStructureGenerating,
         schemeDescriptorsGenerator: SchemeDescriptorsGenerating,
         config: Config = .default)
    {
        self.projectDescriptorGenerator = projectDescriptorGenerator
        self.workspaceStructureGenerator = workspaceStructureGenerator
        self.schemeDescriptorsGenerator = schemeDescriptorsGenerator
        self.config = config
    }

    // MARK: - WorkspaceGenerating

    func generate(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
        let workspaceName = "\(graphTraverser.name).xcworkspace"

        logger.notice("Generating workspace \(workspaceName)", metadata: .section)

        /// Projects
        let projects = try Array(graphTraverser.projects.values)
            .sorted(by: { $0.path < $1.path })
            .compactMap(context: config.projectGenerationContext) { project -> ProjectDescriptor? in
                try projectDescriptorGenerator.generate(project: project, graphTraverser: graphTraverser)
            }

        let generatedProjects: [AbsolutePath: GeneratedProject] = Dictionary(uniqueKeysWithValues: projects.map { project in
            let pbxproj = project.xcodeProj.pbxproj
            let targets = pbxproj.nativeTargets.map {
                ($0.name, $0)
            }
            return (project.xcodeprojPath,
                    GeneratedProject(pbxproj: pbxproj,
                                     path: project.xcodeprojPath,
                                     targets: Dictionary(targets, uniquingKeysWith: { $1 }),
                                     name: project.xcodeprojPath.basename))
        })

        // Workspace structure
        let structure = workspaceStructureGenerator.generateStructure(path: graphTraverser.workspace.path,
                                                                      workspace: graphTraverser.workspace,
                                                                      fileHandler: FileHandler.shared)

        let workspacePath = graphTraverser.workspace.path.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let xcWorkspace = XCWorkspace(data: workspaceData)
        try workspaceData.children = structure.contents.map {
            try recursiveChildElement(generatedProjects: generatedProjects,
                                      element: $0,
                                      path: graphTraverser.path)
        }

        // Schemes
        let schemes = try schemeDescriptorsGenerator.generateWorkspaceSchemes(workspace: graphTraverser.workspace,
                                                                              generatedProjects: generatedProjects,
                                                                              graphTraverser: graphTraverser)

        return WorkspaceDescriptor(
            path: graphTraverser.workspace.path,
            xcworkspacePath: workspacePath,
            xcworkspace: xcWorkspace,
            projectDescriptors: projects,
            schemeDescriptors: schemes,
            sideEffectDescriptors: []
        )
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
                                       path: AbsolutePath) throws -> XCWorkspaceDataElement
    {
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
                throw WorkspaceDescriptorGeneratorError.projectNotFound(path: projectPath)
            }
            let relativePath = generatedProject.path.relative(to: path)
            return workspaceFileElement(path: relativePath)
        }
    }
}
