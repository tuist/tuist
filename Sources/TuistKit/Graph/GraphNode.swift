import Basic
import Foundation
import TuistCore

class GraphNode: Equatable, Hashable {
    // MARK: - Attributes

    let path: AbsolutePath

    // MARK: - Init

    init(path: AbsolutePath) {
        self.path = path
    }

    // MARK: - Equatable

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        return lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

class TargetNode: GraphNode {
    // MARK: - Attributes

    let project: Project
    let target: Target
    var dependencies: [GraphNode]

    // MARK: - Init

    init(project: Project,
         target: Target,
         dependencies: [GraphNode]) {
        self.project = project
        self.target = target
        self.dependencies = dependencies
        super.init(path: project.path)
    }

    override func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(target.name)
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
            try node(for: $0, path: path, name: name, cache: cache, circularDetector: circularDetector, modelLoader: modelLoader)
        }

        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        circularDetector.complete(GraphCircularDetectorNode(path: path, name: name))
        cache.add(targetNode: targetNode)
        return targetNode
    }

    static func node(for dependency: Dependency,
                     path: AbsolutePath,
                     name: String,
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
        }
    }
}

enum PrecompiledNodeError: FatalError, Equatable {
    case architecturesNotFound(AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.asString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .architecturesNotFound:
            return .abort
        }
    }

    // MARK: - Equatable

    static func == (lhs: PrecompiledNodeError, rhs: PrecompiledNodeError) -> Bool {
        switch (lhs, rhs) {
        case let (.architecturesNotFound(lhsPath), .architecturesNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

class PrecompiledNode: GraphNode {
    enum Linking {
        case `static`, dynamic
    }

    enum Architecture: String {
        case x8664 = "x86_64"
        case i386
        case armv7
        case armv7s
    }

    var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    func architectures(system: Systeming = System()) throws -> [Architecture] {
        let result = try system.capture("/usr/bin/lipo", "-info", binaryPath.asString).spm_chuzzle() ?? ""
        let regex = try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: [])
        guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.count)) else {
            throw PrecompiledNodeError.architecturesNotFound(binaryPath)
        }
        let architecturesString = (result as NSString).substring(with: match.range(at: 1))
        return architecturesString.split(separator: " ").map(String.init).compactMap(Architecture.init)
    }

    func linking(system: Systeming = System()) throws -> Linking {
        let result = try system.capture("/usr/bin/file", binaryPath.asString).spm_chuzzle() ?? ""
        return result.contains("dynamically linked") ? .dynamic : .static
    }
}

class FrameworkNode: PrecompiledNode {
    static func parse(projectPath: AbsolutePath,
                      path: RelativePath,
                      cache: GraphLoaderCaching) throws -> FrameworkNode {
        let absolutePath = projectPath.appending(path)
        if let frameworkNode = cache.precompiledNode(absolutePath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: absolutePath)
        cache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    var isCarthage: Bool {
        return path.asString.contains("Carthage/Build")
    }

    override var binaryPath: AbsolutePath {
        let frameworkName = path.components.last!.replacingOccurrences(of: ".framework", with: "")
        return path.appending(component: frameworkName)
    }
}

class LibraryNode: PrecompiledNode {
    // MARK: - Attributes

    let publicHeaders: AbsolutePath
    let swiftModuleMap: AbsolutePath?

    // MARK: - Init

    init(path: AbsolutePath,
         publicHeaders: AbsolutePath,
         swiftModuleMap: AbsolutePath? = nil) {
        self.publicHeaders = publicHeaders
        self.swiftModuleMap = swiftModuleMap
        super.init(path: path)
    }

    static func parse(publicHeaders: RelativePath,
                      swiftModuleMap: RelativePath?,
                      projectPath: AbsolutePath,
                      path: RelativePath,
                      fileHandler: FileHandling,
                      cache: GraphLoaderCaching) throws -> LibraryNode {
        let libraryAbsolutePath = projectPath.appending(path)
        if !fileHandler.exists(libraryAbsolutePath) {
            throw GraphLoadingError.missingFile(libraryAbsolutePath)
        }
        if let libraryNode = cache.precompiledNode(libraryAbsolutePath) as? LibraryNode { return libraryNode }
        let publicHeadersPath = projectPath.appending(publicHeaders)
        if !fileHandler.exists(publicHeadersPath) {
            throw GraphLoadingError.missingFile(publicHeadersPath)
        }
        var swiftModuleMapPath: AbsolutePath?
        if let swiftModuleMapRelativePath = swiftModuleMap {
            swiftModuleMapPath = projectPath.appending(swiftModuleMapRelativePath)
            if !fileHandler.exists(swiftModuleMapPath!) {
                throw GraphLoadingError.missingFile(swiftModuleMapPath!)
            }
        }
        let libraryNode = LibraryNode(path: libraryAbsolutePath,
                                      publicHeaders: publicHeadersPath,
                                      swiftModuleMap: swiftModuleMapPath)
        cache.add(precompiledNode: libraryNode)
        return libraryNode
    }

    override var binaryPath: AbsolutePath {
        return path
    }
}
