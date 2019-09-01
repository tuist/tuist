import Basic
import Foundation
import TuistCore

class PackageNode: GraphNode {
    let packageType: Dependency.PackageType

    init(packageType: Dependency.PackageType, path: AbsolutePath) {
        self.packageType = packageType
        let name: String
        switch packageType {
        case let .local(path: _, productName: productName):
            name = productName
        case let .remote(url: _, productName: productName, versionRequirement: _):
            name = productName
        }
        super.init(path: path, name: name)
    }

    /// Reads the Package node. If it it exists in the cache, it returns it from the cache.
    /// Otherwise, it initializes it, stores it in the cache, and then returns it.
    ///
    /// - Parameters:
    ///   - path: Path to the directory that contains the Podfile.
    ///   - cache: Cache instance where the nodes are cached.
    /// - Returns: The initialized instance of the Package node.
    static func read(
        packageType: Dependency.PackageType,
        path: AbsolutePath,
        cache: GraphLoaderCaching
    ) -> PackageNode {
        if let cached = cache.package(path) { return cached }
        let node = PackageNode(packageType: packageType, path: path)
        cache.add(package: node)
        return node
    }
}
