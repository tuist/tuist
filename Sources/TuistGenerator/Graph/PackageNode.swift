import Basic
import Foundation
import TuistCore

class PackageDependencyNode: GraphNode {
    let product: String
    init(product: String, path: AbsolutePath) {
        self.product = product
        super.init(path: path, name: product)
    }
}

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
