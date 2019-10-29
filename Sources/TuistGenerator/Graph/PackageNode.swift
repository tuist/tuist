import Basic
import Foundation
import TuistCore

/// Node specifying a product dependency on a swift package
class PackageProductNode: GraphNode {
    let product: String
    init(product: String, path: AbsolutePath) {
        self.product = product
        super.init(path: path, name: product)
    }
}

/// Node specifying a swift package
class PackageNode: GraphNode {
    let package: Package

    init(package: Package, path: AbsolutePath) {
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
