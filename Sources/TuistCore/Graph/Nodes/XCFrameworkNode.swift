import Foundation
import TSCBasic
import TuistSupport

public class XCFrameworkNode: PrecompiledNode {
    /// It represents a dependency of an .xcframework which can be either a framework, or another .xcframework.
    public enum Dependency: Equatable {
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

    /// Coding keys.
    enum XCFrameworkNodeCodingKeys: String, CodingKey {
        case linking
        case type
        case path
        case name
        case infoPlist = "info_plist"
    }

    /// The xcframework's Info.plist content.
    public let infoPlist: XCFrameworkInfoPlist

    /// Path to the primary binary.
    public let primaryBinaryPath: AbsolutePath

    /// Returns the type of linking
    public let linking: BinaryLinking

    /// List of other .xcframeworks this xcframework depends on.
    public private(set) var dependencies: [Dependency]

    /// Path to the binary.
    override public var binaryPath: AbsolutePath { primaryBinaryPath }

    /// Initializes the node with its attributes.
    /// - Parameters:
    ///   - path: Path to the .xcframework.
    ///   - infoPlist: The xcframework's Info.plist content.
    ///   - primaryBinaryPath: Path to the primary binary.
    ///   - linking: Returns the type of linking.
    ///   - dependencies: List of dependencies the xcframework depends on.
    public init(path: AbsolutePath,
                infoPlist: XCFrameworkInfoPlist,
                primaryBinaryPath: AbsolutePath,
                linking: BinaryLinking,
                dependencies: [Dependency] = [])
    {
        self.infoPlist = infoPlist
        self.linking = linking
        self.primaryBinaryPath = primaryBinaryPath
        self.dependencies = dependencies
        super.init(path: path)
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: XCFrameworkNodeCodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(linking, forKey: .linking)
        try container.encode("xcframework", forKey: .type)
        try container.encode(infoPlist, forKey: .infoPlist)
    }

    /// Adds a new dependency to the xcframework node.
    /// - Parameter dependency: Dependency to be added.
    public func add(dependency: Dependency) {
        dependencies.append(dependency)
    }
}
