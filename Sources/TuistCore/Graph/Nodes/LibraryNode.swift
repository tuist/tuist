import Foundation
import TSCBasic
import TuistSupport

public class LibraryNode: PrecompiledNode {
    // MARK: - Attributes

    /// Directory that contains the public headers of the library.
    public let publicHeaders: AbsolutePath

    /// Path to the Swift module map file.
    public let swiftModuleMap: AbsolutePath?

    /// List of supported architectures.
    public let architectures: [BinaryArchitecture]

    /// Type of linking supported by the binary.
    public let linking: BinaryLinking

    /// Library product.
    public var product: Product {
        if linking == .static {
            return .staticLibrary
        } else {
            return .dynamicLibrary
        }
    }

    // MARK: - Init

    init(path: AbsolutePath,
         publicHeaders: AbsolutePath,
         architectures: [BinaryArchitecture],
         linking: BinaryLinking,
         swiftModuleMap: AbsolutePath? = nil)
    {
        self.publicHeaders = publicHeaders
        self.swiftModuleMap = swiftModuleMap
        self.architectures = architectures
        self.linking = linking
        super.init(path: path)
    }

    override public func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(publicHeaders)
        hasher.combine(swiftModuleMap)
        hasher.combine(architectures)
        hasher.combine(linking)
    }

    static func == (lhs: LibraryNode, rhs: LibraryNode) -> Bool {
        lhs.isEqual(to: rhs) && rhs.isEqual(to: lhs)
    }

    override func isEqual(to otherNode: GraphNode) -> Bool {
        guard let otherLibraryNode = otherNode as? LibraryNode else {
            return false
        }
        return path == otherLibraryNode.path
            && swiftModuleMap == otherLibraryNode.swiftModuleMap
            && publicHeaders == otherLibraryNode.publicHeaders
            && architectures == otherLibraryNode.architectures
            && linking == otherLibraryNode.linking
    }

    override public var binaryPath: AbsolutePath {
        path
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(product, forKey: .product)
        try container.encode(architectures.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }
}
