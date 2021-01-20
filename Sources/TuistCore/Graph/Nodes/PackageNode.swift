import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

@available(*, deprecated, message: "Package product nodes are deprecated. Dependencies should be usted instead with the ValueGraph.")
/// Node specifying a product dependency on a swift package
public class PackageProductNode: GraphNode {
    public let product: String
    public init(product: String, path: AbsolutePath) {
        self.product = product
        super.init(path: path, name: product)
    }
}

@available(*, deprecated, message: "Package nodes are deprecated. Dependencies should be usted instead with the ValueGraph.")
/// Node specifying a swift package
public class PackageNode: GraphNode {
    public let package: Package

    public init(package: Package, path: AbsolutePath) {
        self.package = package

        let name: String

        switch package {
        case let .local(path: path):
            name = path.pathString
        case let .remote(url: url, requirement: _):
            name = url
        }

        super.init(path: path, name: name)
    }
}
