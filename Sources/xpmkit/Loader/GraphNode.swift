import Basic
import Foundation
import xpmcore

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

    var hashValue: Int {
        return path.hashValue
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

    override var hashValue: Int {
        return path.hashValue ^ target.name.hashValue
    }

    static func read(name: String,
                     path: AbsolutePath,
                     cache: GraphLoaderCaching,
                     graphCircularDetector: GraphCircularDetecting) throws -> TargetNode {
        if let targetNode = cache.targetNode(path, name: name) { return targetNode }
        let project = try Project.at(path, cache: cache)

        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }
        let dependencyMapper = TargetNode.readDependency(path: path, name: name, cache: cache, graphCircularDetector: graphCircularDetector)
        let dependencies: [GraphNode] = try target.dependencies.compactMap(dependencyMapper)
        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        graphCircularDetector.complete(GraphCircularDetectorNode(path: path, name: name))
        cache.add(targetNode: targetNode)
        return targetNode
    }

    static func readDependency(path: AbsolutePath,
                               name: String,
                               cache: GraphLoaderCaching,
                               graphCircularDetector: GraphCircularDetecting,
                               fileHandler: FileHandling = FileHandler()) -> (_ dictionary: JSON) throws -> GraphNode {
        return { json in
            let type: String = try json.get("type")
            if type == "target" {
                let circularFrom = GraphCircularDetectorNode(path: path, name: name)
                let name: String = try json.get("name")
                let circularTo = GraphCircularDetectorNode(path: path, name: name)
                try graphCircularDetector.start(from: circularFrom, to: circularTo)
                return try TargetNode.read(name: name, path: path, cache: cache, graphCircularDetector: graphCircularDetector)
            } else if type == "project" {
                let circularFrom = GraphCircularDetectorNode(path: path, name: name)
                let name: String = try json.get("target")
                let projectRelativePath: RelativePath = try RelativePath(json.get("path"))
                let projectPath = path.appending(projectRelativePath)
                let circularTo = GraphCircularDetectorNode(path: projectPath, name: name)
                try graphCircularDetector.start(from: circularFrom, to: circularTo)
                return try TargetNode.read(name: name, path: path, cache: cache, graphCircularDetector: graphCircularDetector)
            } else if type == "framework" {
                let frameworkPath: RelativePath = try RelativePath(json.get("path"))
                return try FrameworkNode.parse(projectPath: path,
                                               path: frameworkPath,
                                               fileHandler: fileHandler,
                                               cache: cache)
            } else if type == "library" {
                let libraryPath: RelativePath = try RelativePath(json.get("path"))
                return try LibraryNode.parse(json: json,
                                             projectPath: path,
                                             path: libraryPath,
                                             fileHandler: fileHandler,
                                             cache: cache)
            } else {
                fatalError("Invalid dependency type: \(type)")
            }
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

    func architectures(shell: Shelling) throws -> [Architecture] {
        let output = try shell.runAndOutput("lipo -info \(binaryPath.asString)", environment: [:])
        let regex = try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: [])
        guard let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.count)) else {
            throw PrecompiledNodeError.architecturesNotFound(binaryPath)
        }
        let architecturesString = (output as NSString).substring(with: match.range(at: 1))
        return architecturesString.split(separator: " ").map(String.init).compactMap(Architecture.init)
    }

    func linking(shell: Shelling) throws -> Linking {
        let output = try shell.runAndOutput("file \(binaryPath.asString)", environment: [:])
        return output.contains("dynamically linked") ? .dynamic : .static
    }
}

class FrameworkNode: PrecompiledNode {
    static func parse(projectPath: AbsolutePath,
                      path: RelativePath,
                      fileHandler: FileHandling,
                      cache: GraphLoaderCaching) throws -> FrameworkNode {
        let absolutePath = projectPath.appending(path)
        if !fileHandler.exists(absolutePath) {
            throw GraphLoadingError.missingFile(absolutePath)
        }
        if let frameworkNode = cache.precompiledNode(absolutePath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: absolutePath)
        cache.add(precompiledNode: framewokNode)
        return framewokNode
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

    static func parse(json: JSON,
                      projectPath: AbsolutePath,
                      path: RelativePath,
                      fileHandler: FileHandling,
                      cache: GraphLoaderCaching) throws -> LibraryNode {
        let libraryAbsolutePath = projectPath.appending(path)
        if !fileHandler.exists(libraryAbsolutePath) {
            throw GraphLoadingError.missingFile(libraryAbsolutePath)
        }
        if let libraryNode = cache.precompiledNode(libraryAbsolutePath) as? LibraryNode { return libraryNode }
        let publicHeadersRelativePath: RelativePath = try RelativePath(json.get("public_headers"))
        let publicHeadersPath = projectPath.appending(publicHeadersRelativePath)
        if !fileHandler.exists(publicHeadersPath) {
            throw GraphLoadingError.missingFile(publicHeadersPath)
        }
        var swiftModuleMapPath: AbsolutePath?
        if let swiftModuleMapRelativePathString: String = json.get("swift_module_map") {
            let swiftModuleMapRelativePath = RelativePath(swiftModuleMapRelativePathString)
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
