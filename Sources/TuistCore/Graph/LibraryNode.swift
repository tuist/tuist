import Basic
import Foundation
import TuistSupport

public class LibraryNode: PrecompiledNode {
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

    public override func hash(into hasher: inout Hasher) {
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

    static func parse(publicHeaders: AbsolutePath,
                      swiftModuleMap: AbsolutePath?,
                      path: AbsolutePath,
                      cache: GraphLoaderCaching) throws -> LibraryNode {
        if !FileHandler.shared.exists(path) {
            throw GraphLoadingError.missingFile(path)
        }
        if let libraryNode = cache.precompiledNode(path) as? LibraryNode { return libraryNode }

        if !FileHandler.shared.exists(publicHeaders) {
            throw GraphLoadingError.missingFile(publicHeaders)
        }

        if let swiftModuleMap = swiftModuleMap {
            if !FileHandler.shared.exists(swiftModuleMap) {
                throw GraphLoadingError.missingFile(swiftModuleMap)
            }
        }
        let libraryNode = LibraryNode(path: path,
                                      publicHeaders: publicHeaders,
                                      swiftModuleMap: swiftModuleMap)
        cache.add(precompiledNode: libraryNode)
        return libraryNode
    }

    public override var binaryPath: AbsolutePath {
        return path
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let metadataProvider = LibraryMetadataProvider()

        try container.encode(path.pathString, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(try metadataProvider.product(library: self), forKey: .product)
        let archs = try metadataProvider.architectures(precompiled: self)
        try container.encode(archs.map(\.rawValue), forKey: .architectures)
        try container.encode("precompiled", forKey: .type)
    }
}
