import Basic
import Foundation
import TuistCore

class TargetNode: GraphNode {
    // MARK: - Attributes

    let project: Project
    let target: Target
    var dependencies: [GraphNode]

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case platform
        case product
        case bundleId = "bundle_id"
        case dependencies
        case type
    }

    // MARK: - Init

    init(project: Project,
         target: Target,
         dependencies: [GraphNode]) {
        self.project = project
        self.target = target
        self.dependencies = dependencies
        super.init(path: project.path, name: target.name)
    }

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(target.name)
    }

    static func == (lhs: TargetNode, rhs: TargetNode) -> Bool {
        return lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    override func isEqual(to otherNode: GraphNode) -> Bool {
        guard let otherTagetNode = otherNode as? TargetNode else {
            return false
        }
        return path == otherTagetNode.path
            && target == otherTagetNode.target
    }

    static func read(name: String,
                     path: AbsolutePath,
                     cache: GraphLoaderCaching,
                     circularDetector: GraphCircularDetecting,
                     modelLoader: GeneratorModelLoading) throws -> TargetNode {
        if let targetNode = cache.targetNode(path, name: name) { return targetNode }
        let project = try Project.at(path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)

        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }

        let dependencies: [GraphNode] = try target.dependencies.map {
            try node(for: $0,
                     path: path,
                     name: name,
                     platform: target.platform,
                     cache: cache,
                     circularDetector: circularDetector,
                     modelLoader: modelLoader)
        }

        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        circularDetector.complete(GraphCircularDetectorNode(path: path, name: name))
        cache.add(targetNode: targetNode)
        return targetNode
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(target.name, forKey: .name)
        try container.encode(target.platform.rawValue, forKey: .platform)
        try container.encode(target.product.rawValue, forKey: .product)
        try container.encode(target.bundleId, forKey: .bundleId)
        try container.encode("source", forKey: .type)

        let dependencies = self.dependencies.compactMap { (dependency) -> String? in
            if let targetDependency = dependency as? TargetNode {
                return targetDependency.target.name
            } else if let precompiledDependency = dependency as? PrecompiledNode {
                return precompiledDependency.name
            } else {
                return nil
            }
        }
        try container.encode(dependencies, forKey: .dependencies)
    }

    static func node(for dependency: Dependency,
                     path: AbsolutePath,
                     name: String,
                     platform: Platform,
                     cache: GraphLoaderCaching,
                     circularDetector: GraphCircularDetecting,
                     modelLoader: GeneratorModelLoading,
                     fileHandler: FileHandling = FileHandler()) throws -> GraphNode {
        switch dependency {
        case let .target(target):
            let circularFrom = GraphCircularDetectorNode(path: path, name: name)
            let circularTo = GraphCircularDetectorNode(path: path, name: target)
            try circularDetector.start(from: circularFrom, to: circularTo)
            return try TargetNode.read(name: target, path: path, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        case let .project(target, projectRelativePath):
            let circularFrom = GraphCircularDetectorNode(path: path, name: name)
            let projectPath = path.appending(projectRelativePath)
            let circularTo = GraphCircularDetectorNode(path: projectPath, name: target)
            try circularDetector.start(from: circularFrom, to: circularTo)
            return try TargetNode.read(name: target, path: projectPath, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        case let .framework(frameworkPath):
            return try FrameworkNode.parse(projectPath: path,
                                           path: frameworkPath,
                                           cache: cache)
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return try LibraryNode.parse(publicHeaders: publicHeaders,
                                         swiftModuleMap: swiftModuleMap,
                                         projectPath: path,
                                         path: libraryPath,
                                         fileHandler: fileHandler, cache: cache)
        case let .sdk(name, status):
            return try SDKNode(name: name, platform: platform, status: status)
        }
    }
}
