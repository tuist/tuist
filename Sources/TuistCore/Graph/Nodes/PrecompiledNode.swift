import Foundation
import TSCBasic
import TuistSupport

public class PrecompiledNode: GraphNode {
    /// It represents a dependency of a precompiled node, which can be either a framework, or another .xcframework.
    public enum Dependency: Equatable, Hashable {
        case framework(FrameworkNode)
        case xcframework(XCFrameworkNode)

        /// Path to the dependency.
        public var path: AbsolutePath {
            switch self {
            case let .framework(framework): return framework.path
            case let .xcframework(xcframework): return xcframework.path
            }
        }

        /// Returns the node that represents the dependency.
        public var node: PrecompiledNode {
            switch self {
            case let .framework(framework): return framework
            case let .xcframework(xcframework): return xcframework
            }
        }
    }

    /// List of other precompiled artifacts this precompiled node depends on.
    public private(set) var dependencies: [Dependency]

    public init(path: AbsolutePath, dependencies: [Dependency] = []) {
        /// Returns the name of the precompiled node removing the extension
        /// Alamofire.framework -> Alamofire
        /// libAlamofire.a -> libAlamofire
        let name = String(path.components.last!.split(separator: ".").first!)
        self.dependencies = dependencies
        super.init(path: path, name: name)
    }

    public var binaryPath: AbsolutePath {
        fatalError("This method should be overriden by the subclasses")
    }

    /// - Returns: True if node is dynamic and linkable
    public func isDynamicAndLinkable() -> Bool {
        if let framework = self as? FrameworkNode { return framework.linking == .dynamic }
        if let xcframework = self as? XCFrameworkNode { return xcframework.linking == .dynamic }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case architectures
        case product
        case type
    }

    /// Adds a new dependency to the xcframework node.
    /// - Parameter dependency: Dependency to be added.
    public func add(dependency: Dependency) {
        dependencies.append(dependency)
    }
    
    // MARK:  - CustomDebugStringConvertible
    
    override public var debugDescription: String {
        if dependencies.isEmpty {
            return name
        }
        var dependenciesDescriptions: [String] = []
        let uniqueDependencies = Set<Dependency>(dependencies)
        uniqueDependencies.forEach { dependency in
            dependenciesDescriptions.append(dependency.node.description)
        }

        return "\(name) --> [\(dependenciesDescriptions.joined(separator: ", "))]"
    }
}
