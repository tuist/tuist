import Basic
import Foundation
import TuistSupport

public class FrameworkNode: PrecompiledNode {
    /// Path to the associated .dSYM
    let dsymPath: AbsolutePath?

    /// Paths to the bcsymbolmap files.
    let bcsymbolmapPaths: [AbsolutePath]

    /// Returns the type of linking
    let linking: BinaryLinking

    /// The architectures supported by the binary.
    let architectures: [BinaryArchitecture]

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
    public override var binaryPath: AbsolutePath {
        FrameworkNode.binaryPath(frameworkPath: path)
    }

    init(path: AbsolutePath,
         dsymPath: AbsolutePath?,
         bcsymbolmapPaths: [AbsolutePath],
         linking: BinaryLinking,
         architectures: [BinaryArchitecture] = []) {
        self.dsymPath = dsymPath
        self.bcsymbolmapPaths = bcsymbolmapPaths
        self.linking = linking
        self.architectures = architectures
        super.init(path: path)
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(product, forKey: .product)
        try container.encode(architectures.map(\.rawValue), forKey: .architectures)
        try container.encode("framework", forKey: .type)
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    static func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }
}
