import Basic
import Foundation
import TuistCore

class FrameworkNode: PrecompiledNode {
    static func parse(path: AbsolutePath,
                      cache: GraphLoaderCaching) throws -> FrameworkNode {
        if let frameworkNode = cache.precompiledNode(path) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: path)
        cache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    var isCarthage: Bool {
        return path.pathString.contains("Carthage/Build")
    }

    override var binaryPath: AbsolutePath {
        let frameworkName = path.components.last!.replacingOccurrences(of: ".framework", with: "")
        return path.appending(component: frameworkName)
    }

    /// Returns the library product.
    ///
    /// - Returns: Product.
    /// - Throws: An error if the static/dynamic nature of the library cannot be obtained.
    func product() throws -> Product {
        switch try linking() {
        case .dynamic:
            return .framework
        case .static:
            return .staticFramework
        }
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)

        try container.encode(product(), forKey: .product)
        let archs = try architectures()
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }
}
