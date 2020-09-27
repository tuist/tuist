import Foundation
import TSCBasic
import TuistSupport

/// Node specifying a product dependency on a swift package
public class PackageProductNode: GraphNode {
    public let product: String
    public let productType: PackageProductType
    public init(product: String, type: PackageProductType, path: AbsolutePath) {
        self.product = product
        self.productType = type
        super.init(path: path, name: product)
    }
}

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
