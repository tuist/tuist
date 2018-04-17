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

    static func read(name: String, path: AbsolutePath, manifestLoader: GraphManifestLoading, cache: GraphLoaderCaching) throws -> TargetNode {
        if let targetNode = cache.node(path) as? TargetNode { return targetNode }
        let project = try Project.read(path: path, manifestLoader: manifestLoader, cache: cache)
        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }
        let dependencyMapper = TargetNode.readDependency(path: path, manifestLoader: manifestLoader, cache: cache)
        let dependencies: [GraphNode] = try target.dependencies.compactMap(dependencyMapper)
        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        cache.add(node: targetNode)
        return targetNode
    }

    static func readDependency(path: AbsolutePath, manifestLoader: GraphManifestLoading, cache: GraphLoaderCaching) -> (_ dictionary: [String: Any]) throws -> GraphNode {
        return { jsonDependency in
            let unboxer = Unboxer(dictionary: jsonDependency)
            let type: String = try unboxer.unbox(key: "type")
            if type == "target" {
                let name: String = try unboxer.unbox(key: "name")
                return try TargetNode.read(name: name, path: path, manifestLoader: manifestLoader, cache: cache)
            } else if type == "project" {
                let name: String = try unboxer.unbox(key: "name")
                let projectRelativePath: Path = try unboxer.unbox(key: "path")
                try projectRelativePath.assertRelative()
                let projectPath = path + projectRelativePath
                return try TargetNode.read(name: name, path: projectPath, manifestLoader: manifestLoader, cache: cache)
            } else if type == "framework" {
                let frameworkRelativePath: Path = try unboxer.unbox(key: "path")
                try frameworkRelativePath.assertRelative()
                let frameworkPath = path + frameworkRelativePath
                return try FrameworkNode.read(dictionary: jsonDependency,
                                              path: frameworkPath,
                                              cache: cache)
            } else if type == "library" {
                let libraryRelativePath: Path = try unboxer.unbox(key: "path")
                try libraryRelativePath.assertRelative()
                let libraryPath = path + libraryRelativePath
                return try LibraryNode.read(dictionary: jsonDependency,
                                            projectPath: path,
                                            path: libraryPath,
                                            cache: cache)
            } else {
                fatalError("Invalid dependency type: \(type)")
            }
        }
    }
}

class FrameworkNode: GraphNode {
    static func read(dictionary _: [String: Any],
                     path: Path,
                     cache: GraphLoaderCaching) throws -> FrameworkNode {
        try path.assertExists()
        if let frameworkNode = cache.node(path) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: path)
        cache.add(node: framewokNode)
        return framewokNode
    }
}

class LibraryNode: GraphNode {
    let publicHeader: Path
    let swiftModuleMap: Path?

    init(path: Path,
         publicHeader: Path,
         swiftModuleMap: Path? = nil) {
        self.publicHeader = publicHeader
        self.swiftModuleMap = swiftModuleMap
        super.init(path: path)
    }

    static func read(dictionary: [String: Any],
                     projectPath: Path,
                     path: Path,
                     cache: GraphLoaderCaching) throws -> LibraryNode {
        try path.assertExists()
        if let libraryNode = cache.node(path) as? LibraryNode { return libraryNode }
        let unboxer = Unboxer(dictionary: dictionary)
        let publicHeadersRelativePath: Path = try unboxer.unbox(key: "public_headers")
        try publicHeadersRelativePath.assertRelative()
        let publicHeadersPath = projectPath + publicHeadersRelativePath
        try publicHeadersPath.assertExists()
        var swiftModuleMapPath: Path?
        if let swiftModuleMapRelativePath: Path = unboxer.unbox(key: "swift_module_map") {
            try swiftModuleMapRelativePath.assertRelative()
            swiftModuleMapPath = projectPath + swiftModuleMapRelativePath
            try swiftModuleMapPath?.assertExists()
        }
        let libraryNode = LibraryNode(path: path,
                                      publicHeader: publicHeadersPath,
                                      swiftModuleMap: swiftModuleMapPath)
        cache.add(node: libraryNode)
        return libraryNode
    }
}
