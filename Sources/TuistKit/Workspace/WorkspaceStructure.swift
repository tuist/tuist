import Foundation
import Basic
import TuistCore

struct WorkspaceStructure {
    
    indirect enum Element: Equatable {
        case file(path: AbsolutePath)
        case folderReference(path: AbsolutePath)
        case group(name: String, contents: [Element])
        case project(path: AbsolutePath)
    }
    
    let name: String
    let contents: [Element]
    
}

struct DirectoryStructure {
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
            case .file(_), .project(_):
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
    
    let path: AbsolutePath
    let fileHandler: FileHandling
    
    let projects: [AbsolutePath]
    let files: [AbsolutePath]
    
    init(path: AbsolutePath, fileHandler: FileHandling = FileHandler(), projects: [AbsolutePath], files: [AbsolutePath]) {
        self.path = path
        self.fileHandler = fileHandler
        self.projects = projects
        self.files = files
    }
    
    indirect enum Node: CustomDebugStringConvertible, Equatable {
        case file(AbsolutePath)
        case project(AbsolutePath)
        case directory(AbsolutePath, DirectoryStructure.Graph)
        
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
            }
        }
        
        var debugDescription: String {
            switch self {
            case let .file(path):
                return "file: \(path.asString)"
            case let .project(path):
                return "project: \(path.asString)"
            case let .directory(path, graph):
                return "directory: \(path.asString) [\(graph.nodes)]"
            }
        }
    }
    
    internal func buildGraph() throws -> Graph {
        return try buildGraph(path: path)
    }
    
    private func buildGraph(path: AbsolutePath) throws -> Graph {
        let root = Graph()
        let allPaths = (projects + files).sorted()
        let projectsCache = Set(projects)
        let filesCache = Set(files)
        
        let commonAncestor = allPaths.reduce(path) { $0.commonAncestor(with: $1) }
        for elementPath in allPaths {
            let relativePath = elementPath.relative(to: commonAncestor)
            var currentNode = root
            var absolutePath = commonAncestor
            for component in relativePath.components.dropLast() {
                absolutePath = absolutePath.appending(component: component)
                currentNode = currentNode.add(.directory(absolutePath))
            }
            
            if projectsCache.contains(elementPath) {
                currentNode.add(.project(elementPath))
            } else if filesCache.contains(elementPath) {
                currentNode.add(.file(elementPath))
            }
        }
        
        return root
    }
    
}

struct WorkspaceStructureFactory {
    
    let path: AbsolutePath
    let workspace: Workspace
    
    let containers: [String] = [
        ".playground",
        ".xcodeproj"
    ]
    
    private func directoryGraphToWorkspaceStructureElement(content: DirectoryStructure.Node) -> WorkspaceStructure.Element? {
        
        switch content {
        case .file(let file):
            return .file(path: file)
        case .directory(let path, _) where path.suffix.map(containers.contains) ?? false:
            return .file(path: path)
        case .project(let path):
            return .project(path: path)
        case .directory(let path, let contents):
            
            if case let .project(path)? = contents.nodes.first, contents.nodes.count == 1 {
                return .project(path: path)
            } else if contents.nodes.containsProjectInGraph() {
                return .group(name: path.basename, contents: contents.nodes.compactMap(directoryGraphToWorkspaceStructureElement))
            } else {
                return .folderReference(path: path)
            }
            
        }
        
    }
    
    func makeWorkspaceStructure() throws -> WorkspaceStructure {
        let graph = try DirectoryStructure(path: path, projects: workspace.projects, files: workspace.additionalFiles).buildGraph()
        return WorkspaceStructure(name: workspace.name, contents: graph.nodes.compactMap(directoryGraphToWorkspaceStructureElement))
    }
    
}

extension Sequence where Element == AbsolutePath {
    
    func contains(fileName: String) -> Bool {
        return contains(where: { $0.basename == fileName })
    }
    
    func matches(path: AbsolutePath) -> Bool {
        return contains(where: { $0.contains(path) || path.contains($0) })
    }
    
}

extension Sequence where Element == DirectoryStructure.Node {
    
    func files() -> [AbsolutePath] {
        return compactMap{ content in
            switch content {
            case .file(let path): return path
            case .directory, .project: return nil
            }
        }
    }
    
    func contains(fileName: String) -> Bool {
        return files().contains(fileName: fileName)
    }
    
    func containsProjectInGraph() -> Bool {
        
        return first { node in
            switch node {
            case .project: return true
            case .directory(_, let graph): return graph.nodes.containsProjectInGraph()
            case _: return false
            }
            } != nil
        
    }
    
}
