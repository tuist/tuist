import Foundation

@testable import TuistDependencies

public extension PackageDependency {
    static func test(
        name: String = "Package",
        url: String = "https://github.com/Package/Package.git",
        version: String = "1.0.0",
        path: String = "/Users/Admin/Documents/Project/.build/checkouts/Package",
        dependencies: [PackageDependency] = []
    ) -> Self {
        .init(
            name: name,
            url: url,
            version: version,
            path: path,
            dependencies: dependencies
        )
    }
}
