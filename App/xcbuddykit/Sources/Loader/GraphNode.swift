import Foundation
import Basic

class GraphNode {
    let path: AbsolutePath
    init(path: AbsolutePath) {
        self.path = path
    }
}

class TargetNode: GraphNode {
    let project: Project
    let target: Target
    var dependencies: [GraphNode]

    init(project: Project,
         target: Target,
         dependencies: [GraphNode]) {
        self.project = project
        self.target = target
        self.dependencies = dependencies
        super.init(path: project.path)
    }

    static func read(name: String, path: AbsolutePath, context: GraphLoaderContexting) throws -> TargetNode {
        if let targetNode = context.cache.node(path) as? TargetNode { return targetNode }
        let project = try Project.read(path: path, context: context)
        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }
        let dependencyMapper = TargetNode.readDependency(path: path, context: context)
        let dependencies: [GraphNode] = try target.dependencies.compactMap(dependencyMapper)
        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        context.cache.add(node: targetNode)
        return targetNode
    }

    static func readDependency(path: AbsolutePath, context: GraphLoaderContexting) -> (_ dictionary: JSON) throws -> GraphNode {
        return { json in
            let type: String = try json.get("type")
            if type == "target" {
                let name: String = try json.get("name")
                return try TargetNode.read(name: name, path: path, context: context)
            } else if type == "project" {
                let name: String = try json.get("name")
                let projectRelativePath: RelativePath = try RelativePath(json.get("path"))
                let projectPath = path.appending(projectRelativePath)
                return try TargetNode.read(name: name, path: projectPath, context: context)
            } else if type == "framework" {
                let frameworkRelativePath: RelativePath = try RelativePath(json.get("path"))
                let frameworkPath = path.appending(frameworkRelativePath)
                return try FrameworkNode.read(json: json,
                                              path: frameworkPath,
                                              context: context)
            } else if type == "library" {
                let libraryRelativePath: RelativePath = try RelativePath(json.get("path"))
                let libraryPath = path.appending(libraryRelativePath)
                return try LibraryNode.read(json: json,
                                            path: libraryPath,
                                            context: context)
            } else {
                fatalError("Invalid dependency type: \(type)")
            }
        }
    }
}

class FrameworkNode: GraphNode {
    static func read(json: JSON,
                     path: AbsolutePath,
                     context: GraphLoaderContexting) throws -> FrameworkNode {
        if let frameworkNode = context.cache.node(path) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: path)
        context.cache.add(node: framewokNode)
        return framewokNode
    }
}

class LibraryNode: GraphNode {
    let publicHeader: AbsolutePath
    let swiftModuleMap: AbsolutePath?

    init(path: AbsolutePath,
         publicHeader: AbsolutePath,
         swiftModuleMap: AbsolutePath? = nil) {
        self.publicHeader = publicHeader
        self.swiftModuleMap = swiftModuleMap
        super.init(path: path)
    }

    static func read(json: JSON,
                     path: AbsolutePath,
                     context: GraphLoaderContexting) throws -> LibraryNode {
        if let libraryNode = context.cache.node(path) as? LibraryNode { return libraryNode }
        let publicHeadersRelativePath: RelativePath = try RelativePath(json.get("public_headers"))
        let publicHeadersPath = context.projectPath.appending(publicHeadersRelativePath)
        var swiftModuleMapPath: AbsolutePath?
        if let swiftModuleMapRelativePathString: String = json.get("swift_module_map") {
            let swiftModuleMapRelativePath = RelativePath(swiftModuleMapRelativePathString)
            swiftModuleMapPath = context.projectPath.appending(swiftModuleMapRelativePath)
        }
        let libraryNode = LibraryNode(path: path,
                                      publicHeader: publicHeadersPath,
                                      swiftModuleMap: swiftModuleMapPath)
        context.cache.add(node: libraryNode)
        return libraryNode
    }
}
