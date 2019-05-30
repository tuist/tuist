import Basic
import Foundation
import TuistCore

public class GraphNode: Equatable, Hashable, Encodable {
    // MARK: - Attributes

    let path: AbsolutePath

    // MARK: - Init

    init(path: AbsolutePath) {
        self.path = path
    }

    // MARK: - Equatable

    public static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        return lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    func isEqual(to otherNode: GraphNode) -> Bool {
        return path == otherNode.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

public class TargetNode: GraphNode {
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
        super.init(path: project.path)
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(target.name)
    }

    public static func == (lhs: TargetNode, rhs: TargetNode) -> Bool {
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

    public override func encode(to encoder: Encoder) throws {
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

enum PrecompiledNodeError: FatalError, Equatable {
    case architecturesNotFound(AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .architecturesNotFound(path):
            return "Couldn't find architectures for binary at path \(path.pathString)"
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

public class SDKNode: GraphNode {
    let name: String
    let status: SDKStatus
    let type: Type

    init(name: String,
         platform: Platform,
         status: SDKStatus) throws {
        let sdk = AbsolutePath("/\(name)")

        guard let sdkExtension = sdk.extension,
            let type = Type(rawValue: sdkExtension) else {
            throw Error.unsupported(sdk: name)
        }

        self.name = name
        self.status = status
        self.type = type

        let sdkRootPath = AbsolutePath(platform.xcodeSdkRootPath,
                                       relativeTo: AbsolutePath("/"))

        let path: AbsolutePath
        switch type {
        case .framework:
            path = sdkRootPath
                .appending(RelativePath("System/Library/Frameworks"))
                .appending(component: name)
        case .library:
            path = sdkRootPath
                .appending(RelativePath("usr/lib"))
                .appending(component: name)
        }

        super.init(path: path)
    }

    enum `Type`: String, CaseIterable {
        case framework
        case library = "tbd"

        static var supportedTypesDescription: String {
            let supportedTypes = allCases
                .map { ".\($0.rawValue)" }
                .joined(separator: ", ")
            return "[\(supportedTypes)]"
        }
    }

    enum Error: FatalError, Equatable {
        case unsupported(sdk: String)
        var description: String {
            switch self {
            case let .unsupported(sdk):
                let supportedTypes = Type.supportedTypesDescription
                return "The SDK type of \(sdk) is not currently supported - only \(supportedTypes) are supported."
            }
        }

        var type: ErrorType {
            switch self {
            case .unsupported:
                return .abort
            }
        }
    }
}

public class PrecompiledNode: GraphNode {
    enum Linking: String {
        case `static`, dynamic
    }

    enum Architecture: String {
        case x8664 = "x86_64"
        case i386
        case armv7
        case armv7s
        case arm64
    }

    /// Returns the name of the precompiled node removing the extension
    /// Alamofire.framework -> Alamofire
    /// libAlamofire.a -> libAlamofire
    var name: String {
        return String(path.components.last!.split(separator: ".").first!)
    }

    var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    func architectures(system: Systeming = System()) throws -> [Architecture] {
        let result = try system.capture("/usr/bin/lipo", "-info", binaryPath.pathString).spm_chuzzle() ?? ""
        let regexes = [
            // Non-fat file: path is architecture: x86_64
            try NSRegularExpression(pattern: ".+:\\s.+\\sis\\sarchitecture:\\s(.+)", options: []),
            // Architectures in the fat file: /path/xpm.framework/xpm are: x86_64 arm64
            try NSRegularExpression(pattern: "Architectures\\sin\\sthe\\sfat\\sfile:.+:\\s(.+)", options: []),
        ]

        guard let architectures = regexes.compactMap({ (regex) -> [Architecture]? in
            guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.count)) else {
                return nil
            }
            let architecturesString = (result as NSString).substring(with: match.range(at: 1))
            return architecturesString.split(separator: " ").map(String.init).compactMap(Architecture.init)
        }).first else {
            throw PrecompiledNodeError.architecturesNotFound(binaryPath)
        }
        return architectures
    }

    func linking(system: Systeming = System()) throws -> Linking {
        let result = try system.capture("/usr/bin/file", binaryPath.pathString).spm_chuzzle() ?? ""
        return result.contains("dynamically linked") ? .dynamic : .static
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case architectures
        case product
        case type
    }
}

public class FrameworkNode: PrecompiledNode {
    static func parse(projectPath: AbsolutePath,
                      path: RelativePath,
                      cache: GraphLoaderCaching) throws -> FrameworkNode {
        let absolutePath = projectPath.appending(path)
        if let frameworkNode = cache.precompiledNode(absolutePath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: absolutePath)
        cache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    public var isCarthage: Bool {
        return path.pathString.contains("Carthage/Build")
    }

    public override var binaryPath: AbsolutePath {
        let frameworkName = path.components.last!.replacingOccurrences(of: ".framework", with: "")
        return path.appending(component: frameworkName)
    }

    /// Returns the library product.
    ///
    /// - Parameter system: System instance used to determine whether the library is static or dynamic.
    /// - Returns: Product.
    /// - Throws: An error if the static/dynamic nature of the library cannot be obtained.
    func product(system _: Systeming = System()) throws -> Product {
        switch try linking() {
        case .dynamic:
            return .framework
        case .static:
            return .staticFramework
        }
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)

        try container.encode(product(), forKey: .product)
        let archs = try architectures()
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
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

    override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(publicHeaders)
        hasher.combine(swiftModuleMap)
    }

    static func == (lhs: LibraryNode, rhs: LibraryNode) -> Bool {
        return lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    override func isEqual(to otherNode: GraphNode) -> Bool {
        guard let otherLibraryNode = otherNode as? LibraryNode else {
            return false
        }
        return path == otherLibraryNode.path
            && swiftModuleMap == otherLibraryNode.swiftModuleMap
            && publicHeaders == otherLibraryNode.publicHeaders
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

    /// Returns the framework product.
    ///
    /// - Parameter system: System instance used to determine whether the framework is static or dynamic.
    /// - Returns: Product.
    /// - Throws: An error if the static/dynamic nature of the framework cannot be obtained.
    func product(system _: Systeming = System()) throws -> Product {
        switch try linking() {
        case .dynamic:
            return .dynamicLibrary
        case .static:
            return .staticLibrary
        }
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(product(), forKey: .product)
        let archs = try architectures()
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }
}
