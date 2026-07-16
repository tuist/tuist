import Path
import TuistCore
import XcodeGraph

extension GraphTraversing {
    /// Returns, for every local Swift package declared by a graph project, the names of the
    /// package products consumed by that project's targets. These are the buildables Xcode
    /// can gather code coverage for, so scheme code coverage references pointing at a local
    /// package are validated against them.
    func consumedLocalPackageProducts() -> [AbsolutePath: Set<String>] {
        var result: [AbsolutePath: Set<String>] = [:]
        for project in projects.values {
            let localPackagePaths = project.packages.compactMap { package -> AbsolutePath? in
                guard case let .local(path) = package else { return nil }
                return path
            }
            guard !localPackagePaths.isEmpty else { continue }

            let products = project.targets.values
                .flatMap(\.dependencies)
                .compactMap { dependency -> String? in
                    guard case let .package(product, _, _) = dependency else { return nil }
                    return product
                }
            for path in localPackagePaths {
                result[path, default: []].formUnion(products)
            }
        }
        return result
    }
}
