import Foundation
import TSCBasic
import TuistSupport

public class FrameworkNode: PrecompiledNode {
    /// Path to the associated .dSYM
    public let dsymPath: AbsolutePath?

    /// Paths to the bcsymbolmap files.
    public let bcsymbolmapPaths: [AbsolutePath]

    /// Returns the type of linking
    public let linking: BinaryLinking

    /// The architectures supported by the binary.
    public let architectures: [BinaryArchitecture]

    /// Framework dependencies.
    public let dependencies: [FrameworkNode]

    /// Returns the type of product.
    public var product: Product {
        if linking == .static {
            return .staticFramework
        } else {
            return .framework
        }
    }

    /// Returns true if it's a Carthage framework.
    public var isCarthage: Bool {
        path.pathString.contains("Carthage/Build")
    }

    /// Return the framework's binary path.
    override public var binaryPath: AbsolutePath {
        FrameworkNode.binaryPath(frameworkPath: path)
    }

    init(path: AbsolutePath,
         dsymPath: AbsolutePath?,
         bcsymbolmapPaths: [AbsolutePath],
         linking: BinaryLinking,
         architectures: [BinaryArchitecture] = [],
         dependencies: [FrameworkNode] = [])
    {
        self.dsymPath = dsymPath
        self.bcsymbolmapPaths = bcsymbolmapPaths
        self.linking = linking
        self.architectures = architectures
        self.dependencies = dependencies
        super.init(path: path)
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(product, forKey: .product)
        try container.encode(architectures.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    static func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }
}
