import Foundation
import TSCBasic
import TuistSupport
import TuistGraph

@available(*, deprecated, message: "XCFramework nodes are deprecated. Dependencies should be usted instead with the ValueGraph.")
public class XCFrameworkNode: PrecompiledNode {
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
        super.init(path: path, dependencies: dependencies)
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: XCFrameworkNodeCodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(linking, forKey: .linking)
        try container.encode("xcframework", forKey: .type)
        try container.encode(infoPlist, forKey: .infoPlist)
    }
}
