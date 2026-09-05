#if os(macOS)
    import Foundation
    import Mockable
    import Path
    import TuistLoader
    import XcodeGraph

    @Mockable
    protocol LocalPackageProductsMapping {
        func map(graph: Graph, disableSandbox: Bool) async throws -> Graph
    }

    struct LocalPackageProductsMapper: LocalPackageProductsMapping {
        private let manifestLoader: ManifestLoading

        init(manifestLoader: ManifestLoading = ManifestLoader.current) {
            self.manifestLoader = manifestLoader
        }

        func map(graph: Graph, disableSandbox: Bool) async throws -> Graph {
            let packagePaths = Set(
                graph.projects.values
                    .flatMap(\.packages)
                    .compactMap { package -> AbsolutePath? in
                        switch package {
                        case let .local(path: path):
                            return graph.projects[path] == nil ? nil : path
                        case .remote:
                            return nil
                        }
                    }
            )
            guard !packagePaths.isEmpty else { return graph }

            var productDependencies: [String: Set<GraphDependency>] = [:]
            for packagePath in packagePaths.sorted() {
                let packageInfo = try await manifestLoader.loadPackage(at: packagePath, disableSandbox: disableSandbox)
                for product in packageInfo.products {
                    productDependencies[product.name, default: []].formUnion(
                        product.targets.map { GraphDependency.target(name: $0, path: packagePath) }
                    )
                }
            }

            var graph = graph
            graph.dependencies = graph.dependencies.mapValues { dependencies in
                Set(
                    dependencies.flatMap { dependency -> Set<GraphDependency> in
                        guard case let .packageProduct(_, product, _) = dependency,
                              let targets = productDependencies[product]
                        else {
                            return [dependency]
                        }
                        return targets
                    }
                )
            }
            return graph
        }
    }
#endif
