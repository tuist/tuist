import Basic
import Foundation
import TuistCore

class FrameworkNode: PrecompiledNode {
    static func parse(projectPath: AbsolutePath,
                      path: RelativePath,
                      cache: GraphLoaderCaching) throws -> FrameworkNode {
        let absolutePath = projectPath.appending(path)
        if let frameworkNode = cache.precompiledNode(absolutePath) as? FrameworkNode { return frameworkNode }
        let framewokNode = FrameworkNode(path: absolutePath)
        cache.add(precompiledNode: framewokNode)
        return framewokNode
    }

    var isCarthage: Bool {
        return path.pathString.contains("Carthage/Build")
    }

    /// Return the framework's binary path.
    override var binaryPath: AbsolutePath {
        return FrameworkNode.binaryPath(frameworkPath: path)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let metadataProvider = FrameworkMetadataProvider()

        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(try metadataProvider.product(framework: self), forKey: .product)
        let archs = try metadataProvider.architectures(precompiled: self)
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }

    /// Given a framework path it returns the path to its binary.
    /// - Parameter frameworkPath: Framework path.
    static func binaryPath(frameworkPath: AbsolutePath) -> AbsolutePath {
        let frameworkName = frameworkPath.basename.replacingOccurrences(of: ".framework", with: "")
        return frameworkPath.appending(component: frameworkName)
    }
}
