import FileSystem
import Foundation
import Path
import PathKit
import XcodeGraph
import XcodeProj

/// A protocol defining how to map a given file path to a `Graph`.
public protocol XcodeGraphMapping {
    /// Builds a `Graph` from the specified path.
    /// - Parameter path: The absolute path to a `.xcworkspace`, `.xcodeproj`, or directory containing them.
    /// - Returns: A `Graph` representing the projects, targets, and dependencies found at `pathString`.
    /// - Throws: If the path doesn't exist or no projects are found.
    func map(at path: AbsolutePath) async throws -> Graph
}

/// An error type for `XcodeGraphMapper` when the path is invalid or no projects are found.
public enum XcodeGraphMapperError: LocalizedError {
    case pathNotFound(String)
    case noProjectsFound(String)

    public var errorDescription: String? {
        switch self {
        case let .pathNotFound(path):
            return "The specified path does not exist: \(path)"
        case let .noProjectsFound(path):
            return "No `.xcworkspace` or `.xcodeproj` was found at: \(path)"
        }
    }
}

/// Specifies whether we’re mapping a single `.xcodeproj` or an `.xcworkspace`.
enum XcodeMapperGraphType {
    case workspace(XCWorkspace)
    case project(XcodeProj)
}

/// A unified entry point that locates `.xcworkspace` or `.xcodeproj` files—even within directories—and
/// constructs a comprehensive `Graph` of projects, targets, and dependencies.
///
/// Specifically, this mapper:
/// 1. Detects whether the input path is a single project, a workspace, or a directory.
/// 2. Enumerates all discovered targets and dependencies to assemble the final `Graph`.
///
/// This replaces old parsers/providers with a single approach. For example:
/// ```swift
/// let mapper: XcodeGraphMapping = XcodeGraphMapper()
/// let graph = try await mapper.map(at: "/path/to/MyApp")
/// ```
public struct XcodeGraphMapper: XcodeGraphMapping {
    private let fileSystem: FileSysteming
    private let packageInfoLoader: PackageInfoLoading
    private let packageMapper: PackageMapping
    private let projectMapper: PBXProjectMapping

    // MARK: - Initialization

    public init() {
        self.init(fileSystem: FileSystem())
    }

    init(
        fileSystem: FileSysteming = FileSystem(),
        packageInfoLoader: PackageInfoLoading = PackageInfoLoader(),
        packageMapper: PackageMapping = PackageMapper(),
        projectMapper: PBXProjectMapping = PBXProjectMapper()
    ) {
        self.fileSystem = fileSystem
        self.packageInfoLoader = packageInfoLoader
        self.packageMapper = packageMapper
        self.projectMapper = projectMapper
    }

    // MARK: - Public API

    public func map(at path: AbsolutePath) async throws -> Graph {
        guard try await fileSystem.exists(path) else {
            throw XcodeGraphMapperError.pathNotFound(path.pathString)
        }

        let graphType = try await determineGraphType(at: path)
        return try await buildGraph(from: graphType)
    }

    // MARK: - Determine Graph Type

    private func determineGraphType(at path: AbsolutePath) async throws -> XcodeMapperGraphType {
        // Try a direct match for .xcworkspace / .xcodeproj
        if let directType = try detectDirectGraphType(at: path) {
            return directType
        }
        // Otherwise look inside the directory
        return try await detectGraphTypeInDirectory(at: path)
    }

    private func detectDirectGraphType(at path: AbsolutePath) throws -> XcodeMapperGraphType? {
        guard let ext = path.extension?.lowercased() else {
            return nil
        }

        switch ext {
        case "xcworkspace":
            let xcworkspace = try XCWorkspace(path: Path(path.pathString))
            return .workspace(xcworkspace)
        case "xcodeproj":
            let xcodeProj = try XcodeProj(pathString: path.pathString)
            return .project(xcodeProj)
        default:
            return nil
        }
    }

    private func detectGraphTypeInDirectory(at path: AbsolutePath) async throws -> XcodeMapperGraphType {
        let patterns = ["*.xcworkspace", "*.xcodeproj"]
        let contents = try await fileSystem.glob(directory: path, include: patterns).collect()

        if let workspacePath = contents.first(where: { $0.extension?.lowercased() == "xcworkspace" }) {
            let xcworkspace = try XCWorkspace(path: Path(workspacePath.pathString))
            return .workspace(xcworkspace)
        }

        if let projectPath = contents.first(where: { $0.extension?.lowercased() == "xcodeproj" }) {
            let xcodeProj = try XcodeProj(pathString: projectPath.pathString)
            return .project(xcodeProj)
        }

        throw XcodeGraphMapperError.noProjectsFound(path.pathString)
    }

    // MARK: - Build Graph

    func buildGraph(from graphType: XcodeMapperGraphType) async throws -> Graph {
        let projectPaths = try await identifyProjectPaths(from: graphType)
        let workspace = assembleWorkspace(graphType: graphType, projectPaths: projectPaths)
        var projects = try await loadProjects(projectPaths)
        let packages = extractPackages(from: projects)
        var packageInfos: [AbsolutePath: PackageInfo] = [:]
        var packagesByName: [String: AbsolutePath] = [:]
        for projectPackage in projects.values.flatMap(\.packages) {
            switch projectPackage {
            case .remote:
                break
            case let .local(path: packagePath):
                guard packageInfos[packagePath] == nil else { break }
                let packageInfo = try await packageInfoLoader.loadPackageInfo(at: packagePath)
                packageInfos[packagePath] = packageInfo
                packagesByName[packageInfo.name] = packagePath
            }
        }
        for (path, packageInfo) in packageInfos {
            projects[path] = try await packageMapper.map(
                packageInfo,
                packages: packagesByName,
                at: path
            )
        }
        let (dependencies, dependencyConditions) = try await resolveDependencies(for: projects)

        return assembleFinalGraph(
            workspace: workspace,
            projects: projects,
            packages: packages,
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
    }

    private func identifyProjectPaths(from graphType: XcodeMapperGraphType) async throws -> [AbsolutePath] {
        switch graphType {
        case let .workspace(xcworkspace):
            return try await extractProjectPaths(
                from: xcworkspace.data.children,
                srcPath: xcworkspace.workspacePath.parentDirectory
            )
        case let .project(xcodeProj):
            return [xcodeProj.projectPath]
        }
    }

    private func assembleWorkspace(
        graphType: XcodeMapperGraphType,
        projectPaths: [AbsolutePath]
    ) -> Workspace {
        let workspacePath: AbsolutePath
        let name: String

        switch graphType {
        case let .workspace(xcworkspace):
            workspacePath = xcworkspace.workspacePath
            name = workspacePath.basenameWithoutExt
        case let .project(xcodeProj):
            workspacePath = xcodeProj.projectPath.parentDirectory
            name = "Workspace"
        }

        return Workspace(
            path: workspacePath,
            xcWorkspacePath: workspacePath,
            name: name,
            projects: projectPaths
        )
    }

    private func loadProjects(_ projectPaths: [AbsolutePath]) async throws -> [AbsolutePath: Project] {
        var projects = [AbsolutePath: Project]()
        let xcodeProjects = try projectPaths.map {
            try XcodeProj(pathString: $0.pathString)
        }
        let projectNativeTargets: [String: ProjectNativeTarget] = xcodeProjects.reduce(into: [:]) { acc, xcodeProject in
            for nativeTarget in xcodeProject.pbxproj.nativeTargets.sorted(by: { $0.name > $1.name }) {
                let name = Target.sanitizedProductNameFrom(
                    targetName: nativeTarget.productName ?? nativeTarget.name
                )
                acc[name] = ProjectNativeTarget(
                    nativeTarget: nativeTarget,
                    project: xcodeProject
                )
            }
        }

        for xcodeProject in xcodeProjects {
            let project = try await projectMapper.map(
                xcodeProj: xcodeProject,
                projectNativeTargets: projectNativeTargets
            )
            projects[project.path] = project
        }

        return projects
    }

    private func extractPackages(
        from projects: [AbsolutePath: Project]
    ) -> [AbsolutePath: [String: Package]] {
        projects.compactMapValues { project in
            guard !project.packages.isEmpty else { return nil }
            return Dictionary(
                uniqueKeysWithValues: project.packages.map { ($0.url, $0) }
            )
        }
    }

    private func resolveDependencies(
        for projects: [AbsolutePath: Project]
    ) async throws -> ([GraphDependency: Set<GraphDependency>], [GraphEdge: PlatformCondition]) {
        return try await buildDependencies(for: projects)
    }

    private func buildDependencies(
        for projects: [AbsolutePath: Project]
    ) async throws -> ([GraphDependency: Set<GraphDependency>], [GraphEdge: PlatformCondition]) {
        var dependencies = [GraphDependency: Set<GraphDependency>]()
        var dependencyConditions = [GraphEdge: PlatformCondition]()

        for (path, project) in projects {
            for (name, target) in project.targets {
                let sourceDependency = GraphDependency.target(name: name, path: path)

                // Build edges for each target dependency
                let edgesAndDeps = try await target.dependencies.serialCompactMap { (dep: TargetDependency) async throws -> (
                    GraphEdge,
                    PlatformCondition?,
                    GraphDependency
                ) in
                    let graphDep = try await dep.graphDependency(
                        sourceDirectory: path,
                        target: target
                    )
                    return (GraphEdge(from: sourceDependency, to: graphDep), dep.condition, graphDep)
                }

                // Update conditions dictionary
                for (edge, condition, _) in edgesAndDeps {
                    if let condition {
                        dependencyConditions[edge] = condition
                    }
                }

                // Update dependencies dictionary
                let targetDeps = edgesAndDeps.map(\.2)
                if !targetDeps.isEmpty {
                    dependencies[sourceDependency] = Set(targetDeps)
                }
            }
        }
        return (dependencies, dependencyConditions)
    }

    private func assembleFinalGraph(
        workspace: Workspace,
        projects: [AbsolutePath: Project],
        packages: [AbsolutePath: [String: Package]],
        dependencies: [GraphDependency: Set<GraphDependency>],
        dependencyConditions: [GraphEdge: PlatformCondition]
    ) -> Graph {
        Graph(
            name: workspace.name,
            path: workspace.path,
            workspace: workspace,
            projects: projects,
            packages: packages,
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
    }

    // MARK: - Project Path Extraction

    private func extractProjectPaths(
        from elements: [XCWorkspaceDataElement],
        srcPath: AbsolutePath
    ) async throws -> [AbsolutePath] {
        var paths: [AbsolutePath] = []

        for element in elements {
            switch element {
            case let .file(ref):
                let refPath = try await ref.path(srcPath: srcPath)
                if refPath.extension == "xcodeproj" {
                    paths.append(refPath)
                }
            case let .group(group):
                // Set a new src root to account for projects in nested directories
                let recursiveRoot = srcPath.appending(component: group.location.path)

                let nestedPaths = try await extractProjectPaths(from: group.children, srcPath: recursiveRoot)
                paths.append(contentsOf: nestedPaths)
            }
        }

        return paths
    }
}
