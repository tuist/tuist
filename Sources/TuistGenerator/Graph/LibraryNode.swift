import Basic
import Foundation
import TuistCore

class LibraryNode: PrecompiledNode {
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

    override func hash(into hasher: inout Hasher) {
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

    static func parse(publicHeaders: RelativePath,
                      swiftModuleMap: RelativePath?,
                      projectPath: AbsolutePath,
                      path: RelativePath,
                      cache: GraphLoaderCaching) throws -> LibraryNode {
        let libraryAbsolutePath = projectPath.appending(path)
        if !FileHandler.shared.exists(libraryAbsolutePath) {
            throw GraphLoadingError.missingFile(libraryAbsolutePath)
        }
        if let libraryNode = cache.precompiledNode(libraryAbsolutePath) as? LibraryNode { return libraryNode }
        let publicHeadersPath = projectPath.appending(publicHeaders)
        if !FileHandler.shared.exists(publicHeadersPath) {
            throw GraphLoadingError.missingFile(publicHeadersPath)
        }
        var swiftModuleMapPath: AbsolutePath?
        if let swiftModuleMapRelativePath = swiftModuleMap {
            swiftModuleMapPath = projectPath.appending(swiftModuleMapRelativePath)
            if !FileHandler.shared.exists(swiftModuleMapPath!) {
                throw GraphLoadingError.missingFile(swiftModuleMapPath!)
            }
        }
        let libraryNode = LibraryNode(path: libraryAbsolutePath,
                                      publicHeaders: publicHeadersPath,
                                      swiftModuleMap: swiftModuleMapPath)
        cache.add(precompiledNode: libraryNode)
        return libraryNode
    }

    override var binaryPath: AbsolutePath {
        return path
    }

    /// Returns the framework product.
    ///
    /// - Returns: Product.
    /// - Throws: An error if the static/dynamic nature of the framework cannot be obtained.
    func product() throws -> Product {
        switch try linking() {
        case .dynamic:
            return .dynamicLibrary
        case .static:
            return .staticLibrary
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
