import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

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
    func generateStructure(
        path: AbsolutePath,
        workspace: Workspace,
        xcodeProjPaths: [AbsolutePath],
        fileHandler: FileHandling
    ) -> WorkspaceStructure
}

final class WorkspaceStructureGenerator: WorkspaceStructureGenerating {
    func generateStructure(
        path: AbsolutePath,
        workspace: Workspace,
        xcodeProjPaths: [AbsolutePath],
        fileHandler: FileHandling
    ) -> WorkspaceStructure {
        let graph = DirectoryStructure(
            path: path,
            projects: xcodeProjPaths,
            files: workspace.additionalFiles,
            fileHandler: fileHandler
        ).buildGraph()
        return WorkspaceStructure(
            name: workspace.name,
            contents: graph.nodes.compactMap(directoryGraphToWorkspaceStructureElement)
        )
    }

    private func directoryGraphToWorkspaceStructureElement(content: DirectoryStructure.Node) -> WorkspaceStructure.Element? {
        switch content {
        case let .file(file):
            return .file(path: file)
        case let .project(path):
            return .project(path: path)
        case let .directory(path, contents):
            return .group(
                name: path.basename,
                path: path,
                contents: contents.nodes.compactMap(directoryGraphToWorkspaceStructureElement)
            )
        case let .folderReference(path):
            return .folderReference(path: path)
        }
    }
}

private class DirectoryStructure {
    let path: AbsolutePath
    let projects: [AbsolutePath]
    let files: [FileElement]
    let fileHandler: FileHandling

    private let containers: [String] = [
        ".playground",
        ".xcodeproj",
    ]

    init(
        path: AbsolutePath,
        projects: [AbsolutePath],
        files: [FileElement],
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.path = path
        self.projects = projects
        self.files = files
        self.fileHandler = fileHandler
    }

    func buildGraph() -> Graph {
        buildGraph(path: path)
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

    private func fileNode(from element: FileElement) -> Node {
        switch element {
        case let .file(path: path):
            return .file(path)
        case let .folderReference(path: path):
            return .folderReference(path)
        }
    }

    private func projectNode(from path: AbsolutePath) -> Node {
        .project(path)
    }

    private func isFileOrFolderReference(element: FileElement) -> Bool {
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
            nodes.debugDescription
        }

        static func == (lhs: DirectoryStructure.Graph, rhs: DirectoryStructure.Graph) -> Bool {
            lhs.nodes == rhs.nodes
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
            .directory(path, Graph())
        }

        var path: AbsolutePath {
            switch self {
            case let .file(path):
                return path
            case let .project(path):
                return path.parentDirectory
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
            return "file: \(path.pathString)"
        case let .project(path):
            return "project: \(path.pathString)"
        case let .directory(path, graph):
            return "directory: \(path.pathString) > \(graph.nodes)"
        case let .folderReference(path):
            return "folderReference: \(path.pathString)"
        }
    }
}
