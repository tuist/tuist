import Basic
import Foundation
import TuistCore

struct WorkspaceStructure {
    enum Element: Equatable {
        case file(path: AbsolutePath)
        case folderReference(path: AbsolutePath)
        indirect case group(name: String, path: AbsolutePath?, contents: [Element])
        case project(path: AbsolutePath)
    }

    let name: String
    let contents: [Element]
}

protocol WorkspaceStructureGenerating {
    /// Generates a WorkspaceStructure instance which represents the structure of the workspace that needs to be generated.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that will contain the generated workspace.
    ///   - workspace: Workspace manifest representation.
    ///   - manifestProjectPaths: List of paths to the *.xcodeproj projects that have been generated for the manifest files.
    /// - Returns: A WorkspaceStructure that represents the workspace that needs to be generated.
    func generateStructure(path: AbsolutePath, workspace: Workspace, manifestProjectPaths: [AbsolutePath]) -> WorkspaceStructure
}

final class WorkspaceStructureGenerator: WorkspaceStructureGenerating {

    /// Generates a WorkspaceStructure instance which represents the structure of the workspace that needs to be generated.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that will contain the generated workspace.
    ///   - workspace: Workspace manifest representation.
    ///   - manifestProjectPaths: List of paths to the *.xcodeproj projects that have been generated for the manifest files.
    /// - Returns: A WorkspaceStructure that represents the workspace that needs to be generated.
    func generateStructure(path: AbsolutePath,
                           workspace: Workspace,
                           manifestProjectPaths: [AbsolutePath]) -> WorkspaceStructure {
        let graph = DirectoryStructure(path: path,
                                       projects: workspace.projects,
                                       files: workspace.additionalFiles,
                                       manifestProjectPaths: manifestProjectPaths).buildGraph()
        return WorkspaceStructure(name: workspace.name,
                                  contents: graph.nodes.compactMap(directoryGraphToWorkspaceStructureElement))
    }

    private func directoryGraphToWorkspaceStructureElement(content: DirectoryStructure.Node) -> WorkspaceStructure.Element? {
        switch content {
        case let .file(file):
            return .file(path: file)
        case let .project(path):
            return .project(path: path)
        case let .directory(path, contents):
            return .group(name: path.basename,
                          path: path,
                          contents: contents.nodes.compactMap(directoryGraphToWorkspaceStructureElement))
        case let .folderReference(path):
            return .folderReference(path: path)
        case let .group(name, graph):
            return .group(name: name,
                          path: nil,
                          contents: graph.nodes.compactMap(directoryGraphToWorkspaceStructureElement))
        }
    }
}

private class DirectoryStructure {
    let path: AbsolutePath
    let manifestProjectPaths: [AbsolutePath]
    let projects: [AbsolutePath]
    let files: [FileElement]

    private let containers: [String] = [
        ".playground",
        ".xcodeproj",
    ]

    init(path: AbsolutePath,
         projects: [AbsolutePath],
         files: [FileElement],
         manifestProjectPaths: [AbsolutePath]) {
        self.path = path
        self.projects = projects
        self.files = files
        self.manifestProjectPaths = manifestProjectPaths
    }

    func buildGraph() -> Graph {
        return buildGraph(path: path)
    }

    private func buildGraph(path: AbsolutePath) -> Graph {
        let root = Graph()

        // Projects & additional files
        let filesIncludingContainers = files.filter(isFileOrFolderReference)
        let fileNodes = filesIncludingContainers.map(fileNode)
        let projectNodes = projects.map(projectNode)
        let allNodes = (projectNodes + fileNodes).sorted(by: { $0.path! < $1.path! })

        let commonAncestor = allNodes.reduce(path) { $0.commonAncestor(with: $1.path!) }
        for node in allNodes {
            let relativePath = node.path!.relative(to: commonAncestor)
            var currentNode = root
            var absolutePath = commonAncestor
            for component in relativePath.components.dropLast() {
                absolutePath = absolutePath.appending(component: component)
                currentNode = currentNode.add(.directory(absolutePath))
            }

            currentNode.add(node)
        }

        // Manifest projects
        let manifestProjectNodes = Graph(nodes: manifestProjectPaths.map(projectNode))
        let manifestNode = Node.group(name: "Projects", graph: manifestProjectNodes)
        root.add(manifestNode)

        return root
    }

    private func fileNode(from element: FileElement) -> Node {
        switch element {
        case let .file(path: path):
            return .file(path)
        case let .folderReference(path: path):
            return .folderReference(path)
        }
    }

    private func projectNode(from path: AbsolutePath) -> Node {
        return .project(path)
    }

    private func isFileOrFolderReference(element: FileElement) -> Bool {
        switch element {
        case .folderReference:
            return true
        case let .file(path):
            if FileHandler.shared.isFolder(path) {
                return path.suffix.map(containers.contains) ?? false
            }
            return true
        }
    }
}

extension DirectoryStructure {
    class Graph: Equatable, ExpressibleByArrayLiteral, CustomDebugStringConvertible {
        var nodes: [Node] = []
        private var directoryCache: [AbsolutePath: Graph] = [:]

        init(nodes: [DirectoryStructure.Node]) {
            self.nodes = nodes
            directoryCache = Dictionary(uniqueKeysWithValues: nodes.compactMap {
                switch $0 {
                case let .directory(path, graph):
                    return (path, graph)
                default:
                    return nil
                }
            })
        }

        required convenience init(arrayLiteral elements: DirectoryStructure.Node...) {
            self.init(nodes: elements)
        }

        @discardableResult
        func add(_ node: Node) -> Graph {
            switch node {
            case .file, .project, .folderReference, .group:
                nodes.append(node)
                return self
            case let .directory(path, _):
                if let existingNode = directoryCache[path] {
                    return existingNode
                } else {
                    let directoryGraph = Graph()
                    nodes.append(.directory(path, directoryGraph))
                    directoryCache[path] = directoryGraph
                    return directoryGraph
                }
            }
        }

        var debugDescription: String {
            return nodes.debugDescription
        }

        static func == (lhs: DirectoryStructure.Graph,
                        rhs: DirectoryStructure.Graph) -> Bool {
            return lhs.nodes == rhs.nodes
        }
    }
}

extension DirectoryStructure {
    indirect enum Node: Equatable {
        case file(AbsolutePath)
        case project(AbsolutePath)
        case directory(AbsolutePath, DirectoryStructure.Graph)
        case folderReference(AbsolutePath)
        case group(name: String, graph: DirectoryStructure.Graph)

        static func directory(_ path: AbsolutePath) -> Node {
            return .directory(path, Graph())
        }

        var path: AbsolutePath? {
            switch self {
            case let .file(path):
                return path
            case let .project(path):
                return path
            case let .directory(path, _):
                return path
            case let .folderReference(path):
                return path
            case .group:
                return nil
            }
        }
    }
}

extension DirectoryStructure.Node: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case let .file(path):
            return "file: \(path.pathString)"
        case let .project(path):
            return "project: \(path.pathString)"
        case let .directory(path, graph):
            return "directory: \(path.pathString) > \(graph.nodes)"
        case let .folderReference(path):
            return "folderReference: \(path.pathString)"
        case let .group(name, _):
            return "group: \(name)"
        }
    }
}
