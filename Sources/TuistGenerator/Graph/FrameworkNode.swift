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

    override var binaryPath: AbsolutePath {
        let frameworkName = path.components.last!.replacingOccurrences(of: ".framework", with: "")
        return path.appending(component: frameworkName)
    }

    // Vendored frameworks might have a dSYM file next to them so ensure its copied. Frameworks built from
    // sources will have their dSYM generated and copied by Xcode.
    var dsymPath: AbsolutePath? {
        let path = AbsolutePath("\(self.path.pathString).dSYM")
        if FileHandler.shared.exists(path) { return path }
        return nil
    }

    /// Returns the *.bcsymbol maps in the framework's directory that belong
    /// to this framework.
    func bcsymbolmapPaths() throws -> [AbsolutePath] {
        let uuids = try self.uuids()
        return uuids
            .map { self.path.parentDirectory.appending(component: "\($0).bcsymbolmap") }
            .filter { FileHandler.shared.exists($0) }
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
