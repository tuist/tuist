import Basic
import Foundation
import TuistCore

struct WorkspaceStructure {
    enum Element: Equatable {
        case file(path: AbsolutePath)
        case folderReference(path: AbsolutePath)
        indirect case group(name: String, path: AbsolutePath, contents: [Element])
        case project(path: AbsolutePath)
    }

    let name: String
    let contents: [Element]
}

protocol WorkspaceStructureGenerating {
    func generateStructure(path: AbsolutePath, workspace: Workspace) -> WorkspaceStructure
}

final class WorkspaceStructureGenerator: WorkspaceStructureGenerating {
    private let fileHandler: FileHandling

    init(fileHandler: FileHandling) {
        self.fileHandler = fileHandler
    }

    func generateStructure(path: AbsolutePath, workspace: Workspace) -> WorkspaceStructure {
        let graph = DirectoryStructure(path: path,
                                       fileHandler: fileHandler,
                                       projects: workspace.projects,
                                       files: workspace.additionalFiles).buildGraph()
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
        }
    }
}

private class DirectoryStructure {
    let path: AbsolutePath
    let fileHandler: FileHandling

    let projects: [AbsolutePath]
    let files: [Workspace.Element]

    private let containers: [String] = [
        ".playground",
        ".xcodeproj",
    ]

    init(path: AbsolutePath,
         fileHandler: FileHandling,
         projects: [AbsolutePath],
         files: [Workspace.Element]) {
        self.path = path
        self.fileHandler = fileHandler
        self.projects = projects
        self.files = files
    }

    func buildGraph() -> Graph {
        return buildGraph(path: path)
    }

    private func buildGraph(path: AbsolutePath) -> Graph {
        let root = Graph()

        let filesIncludingContainers = files.filter(isFileOrFolderReference)
        let fileNodes = filesIncludingContainers.map(fileNode)
        let projectNodes = projects.map(projectNode)
        let allNodes = (projectNodes + fileNodes).sorted(by: { $0.path < $1.path })

        let commonAncestor = allNodes.reduce(path) { $0.commonAncestor(with: $1.path) }
        for node in allNodes {
            let relativePath = node.path.relative(to: commonAncestor)
            var currentNode = root
            var absolutePath = commonAncestor
            for component in relativePath.components.dropLast() {
                absolutePath = absolutePath.appending(component: component)
                currentNode = currentNode.add(.directory(absolutePath))
            }

            currentNode.add(node)
        }

        return root
    }

    private func fileNode(from element: Workspace.Element) -> Node {
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

    private func isFileOrFolderReference(element: Workspace.Element) -> Bool {
        switch element {
        case .folderReference:
            return true
        case let .file(path):
            if fileHandler.isFolder(path) {
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

        required init(arrayLiteral elements: DirectoryStructure.Node...) {
            nodes = elements
            directoryCache = Dictionary(uniqueKeysWithValues: nodes.compactMap {
                switch $0 {
                case let .directory(path, graph):
                    return (path, graph)
                default:
                    return nil
                }
            })
        }

        @discardableResult
        func add(_ node: Node) -> Graph {
            switch node {
            case .file, .project, .folderReference:
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

        static func directory(_ path: AbsolutePath) -> Node {
            return .directory(path, Graph())
        }

        var path: AbsolutePath {
            switch self {
            case let .file(path):
                return path
            case let .project(path):
                return path
            case let .directory(path, _):
                return path
            case let .folderReference(path):
                return path
            }
        }
    }
}

extension DirectoryStructure.Node: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case let .file(path):
            return "file: \(path.asString)"
        case let .project(path):
            return "project: \(path.asString)"
        case let .directory(path, graph):
            return "directory: \(path.asString) > \(graph.nodes)"
        case let .folderReference(path):
            return "folderReference: \(path.asString)"
        }
    }
}
