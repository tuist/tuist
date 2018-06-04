import Basic
import Foundation

/// Dependency graph node.
class GraphNode: Equatable, Hashable {
    /// Node path.
    let path: AbsolutePath

    /// Initializes the node with its path.
    ///
    /// - Parameter path: path to the node.
    init(path: AbsolutePath) {
        self.path = path
    }

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        return lhs.path == rhs.path
    }

    var hashValue: Int {
        return path.hashValue
    }
}

/// Graph node that represents a project target (to be generaterd).
class TargetNode: GraphNode {
    /// Project that contains the target definition.
    let project: Project

    /// Target definition.
    let target: Target

    /// Node dependencies.
    var dependencies: [GraphNode]

    /// Initializes the target node with its attribute.
    ///
    /// - Parameters:
    ///   - project: project that contains the target definition.
    ///   - target: target description.
    ///   - dependencies: node dependencies.
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

    static func read(name: String, path: AbsolutePath, context: GraphLoaderContexting) throws -> TargetNode {
        if let targetNode = context.cache.targetNode(path, name: name) { return targetNode }
        let project = try Project.at(path, context: context)
        guard let target = project.targets.first(where: { $0.name == name }) else {
            throw GraphLoadingError.targetNotFound(name, path)
        }
        let dependencyMapper = TargetNode.readDependency(path: path, name: name, context: context)
        let dependencies: [GraphNode] = try target.dependencies.compactMap(dependencyMapper)
        let targetNode = TargetNode(project: project, target: target, dependencies: dependencies)
        context.circularDetector.complete(GraphCircularDetectorNode(path: path, name: name))
        context.cache.add(targetNode: targetNode)
        return targetNode
    }

    static func readDependency(path: AbsolutePath, name: String, context: GraphLoaderContexting) -> (_ dictionary: JSON) throws -> GraphNode {
        return { json in
            let type: String = try json.get("type")
            if type == "target" {
                let name: String = try json.get("name")
                let circularFrom = GraphCircularDetectorNode(path: path, name: name)
                let circularTo = GraphCircularDetectorNode(path: path, name: name)
                try context.circularDetector.start(from: circularFrom, to: circularTo)
                return try TargetNode.read(name: name, path: path, context: context)
            } else if type == "project" {
                let circularFrom = GraphCircularDetectorNode(path: path, name: name)
                let name: String = try json.get("target")
                let projectRelativePath: RelativePath = try RelativePath(json.get("path"))
                let projectPath = path.appending(projectRelativePath)
                let circularTo = GraphCircularDetectorNode(path: projectPath, name: name)
                try context.circularDetector.start(from: circularFrom, to: circularTo)
                return try TargetNode.read(name: name, path: projectPath, context: context)
            } else if type == "framework" {
                let frameworkPath: RelativePath = try RelativePath(json.get("path"))
                return try FrameworkNode.parse(projectPath: path,
                                               path: frameworkPath,
                                               context: context)
            } else if type == "library" {
                let libraryPath: RelativePath = try RelativePath(json.get("path"))
                return try LibraryNode.parse(json: json,
                                             projectPath: path,
                                             path: libraryPath,
                                             context: context)
            } else {
                fatalError("Invalid dependency type: \(type)")
            }
        }
    }
}

/// Precompiled node errors.
///
/// - architecturesNotFound: thrown when the architectures cannot be found.
enum PrecompiledNodeError: FatalError, Equatable {
    case architecturesNotFound(AbsolutePath)

    /// Error description.
    var description: String {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.asString)"
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .architecturesNotFound:
            return .abort
        }
    }

    /// Compares two errors.
    ///
    /// - Parameters:
    ///   - lhs: first error to be compared.
    ///   - rhs: second error to be compared.
    /// - Returns: true if the two errors are the same.
    static func == (lhs: PrecompiledNodeError, rhs: PrecompiledNodeError) -> Bool {
        switch (lhs, rhs) {
        case let (.architecturesNotFound(lhsPath), .architecturesNotFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

/// Precompiled node.
class PrecompiledNode: GraphNode {
    /// Binary linking type.
    ///
    /// - `static`: static linking.
    /// - dynamic: dynamic linking.
    enum Linking {
        case `static`, dynamic
    }

    /// Valid binary architectures.
    ///
    /// - x86_64: x86 64 bits.
    /// - i386: i386 (for the simulators)
    /// - armv7: armv7 (OS device)
    /// - armv7s: armv7s (OS device)
    enum Architecture: String {
        case x8664 = "x86_64"
        case i386
        case armv7
        case armv7s
    }

    /// Returns the path to the precompiled binary.
    var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    /// Returns the supported architectures of the precompiled framework/library.
    ///
    /// - Parameter shell: shell needed to execute some commands.
    /// - Returns: list of architectures.
    /// - Throws: an error if architectures cannot be obtained for the framework/library.
    func architectures(shell: Shelling) throws -> [Architecture] {
        let output = try shell.run("lipo -info \(binaryPath.asString)", environment: [:])
        let regex = try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: [])
        guard let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.count)) else {
            throw PrecompiledNodeError.architecturesNotFound(binaryPath)
        }
        let architecturesString = (output as NSString).substring(with: match.range(at: 1))
        return architecturesString.split(separator: " ").map(String.init).compactMap(Architecture.init)
    }

    /// Returns the whether the framework/library should be linked dynamic or statically.
    ///
    /// - Parameter shell: shell util necessary to run some commands to get the linking information.
    /// - Returns: linking type.
    /// - Throws: throws an error if the linking cannot be obtained for the framework/library.
    func linking(shell: Shelling) throws -> Linking {
        let output = try shell.run("file \(binaryPath.asString)", environment: [:])
        return output.contains("dynamically linked") ? .dynamic : .static
    }
}

/// Graph node that represents a framework.
class FrameworkNode: PrecompiledNode {
    /// Parses a framework node.
    ///
    /// - Parameters:
    ///   - projectPath: path to the folder that contains the Project.swift which has a reference to this framework.
    ///   - path: path relative path to the framework.
    ///   - context: graph loader context.
    /// - Returns: framework node.
    /// - Throws: an error if the framework cannot be parsed.
    static func parse(projectPath: AbsolutePath,
                      path: RelativePath,
                      context: GraphLoaderContexting) throws -> FrameworkNode {
        let absolutePath = projectPath.appending(path)
        if !context.fileHandler.exists(absolutePath) {
            throw GraphLoadingError.missingFile(absolutePath)
        }
        if let frameworkNode = context.cache.precompiledNode(absolutePath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: absolutePath)
        context.cache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    /// Returns the path to the framework binary.
    override var binaryPath: AbsolutePath {
        let frameworkName = path.components.last!.replacingOccurrences(of: ".framework", with: "")
        return path.appending(component: frameworkName)
    }
}

/// Library precompiled node.
class LibraryNode: PrecompiledNode {
    /// Path to the public headers folder.
    let publicHeaders: AbsolutePath

    /// Path to the Swift modulemap file.
    let swiftModuleMap: AbsolutePath?

    /// Initializes the library node with its attributes.
    ///
    /// - Parameters:
    ///   - path: path to the library binary.
    ///   - publicHeaders: path to the public headers folder.
    ///   - swiftModuleMap: path to the swift modulemap file.
    init(path: AbsolutePath,
         publicHeaders: AbsolutePath,
         swiftModuleMap: AbsolutePath? = nil) {
        self.publicHeaders = publicHeaders
        self.swiftModuleMap = swiftModuleMap
        super.init(path: path)
    }

    /// Parses the library node from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: JSON representation of the node.
    ///   - projectPath: path to the folder where the Project.swift that references the node is.
    ///   - path: relative path to the library.
    ///   - context: graph loader context.
    /// - Returns: the library node.
    /// - Throws: throws an error if it cannot be parsed.
    static func parse(json: JSON,
                      projectPath: AbsolutePath,
                      path: RelativePath,
                      context: GraphLoaderContexting) throws -> LibraryNode {
        let libraryAbsolutePath = projectPath.appending(path)
        if !context.fileHandler.exists(libraryAbsolutePath) {
            throw GraphLoadingError.missingFile(libraryAbsolutePath)
        }
        if let libraryNode = context.cache.precompiledNode(libraryAbsolutePath) as? LibraryNode { return libraryNode }
        let publicHeadersRelativePath: RelativePath = try RelativePath(json.get("public_headers"))
        let publicHeadersPath = projectPath.appending(publicHeadersRelativePath)
        if !context.fileHandler.exists(publicHeadersPath) {
            throw GraphLoadingError.missingFile(publicHeadersPath)
        }
        var swiftModuleMapPath: AbsolutePath?
        if let swiftModuleMapRelativePathString: String = json.get("swift_module_map") {
            let swiftModuleMapRelativePath = RelativePath(swiftModuleMapRelativePathString)
            swiftModuleMapPath = projectPath.appending(swiftModuleMapRelativePath)
            if !context.fileHandler.exists(swiftModuleMapPath!) {
                throw GraphLoadingError.missingFile(swiftModuleMapPath!)
            }
        }
        let libraryNode = LibraryNode(path: libraryAbsolutePath,
                                      publicHeaders: publicHeadersPath,
                                      swiftModuleMap: swiftModuleMapPath)
        context.cache.add(precompiledNode: libraryNode)
        return libraryNode
    }

    /// Returns the library binary path.
    override var binaryPath: AbsolutePath {
        return path
    }
}
