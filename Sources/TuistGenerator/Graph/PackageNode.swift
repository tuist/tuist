import Basic
import Foundation
import TuistCore

class PackageNode: GraphNode {
    let url: String
    let productName: String
    let versionRequirement: Dependency.VersionRequirement

    init(url: String, productName: String, versionRequirement: Dependency.VersionRequirement, path: AbsolutePath) {
        self.url = url
        self.productName = productName
        self.versionRequirement = versionRequirement
        super.init(path: path, name: productName)
    }
    
    /// Reads the Package node. If it it exists in the cache, it returns it from the cache.
    /// Otherwise, it initializes it, stores it in the cache, and then returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the Podfile.
    ///   - cache: Cache instance where the nodes are cached.
    /// - Returns: The initialized instance of the Package node.
    static func read(
        url: String,
        productName: String,
        versionRequirement: Dependency.VersionRequirement,
        path: AbsolutePath,
        cache: GraphLoaderCaching
    ) -> PackageNode {
        if let cached = cache.package(path) { return cached }
        let node = PackageNode(url: url, productName: productName, versionRequirement: versionRequirement, path: path)
        cache.add(package: node)
        return node
    }
    
}
