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
}
