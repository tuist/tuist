import Foundation
import TSCBasic
import TuistCore

/// Static Products Graph Linter
///
/// A linter that identifies potential issues in a graph where
/// static products are linked multiple times.
///
protocol StaticProductsGraphLinting {
    func lint(graph: Graph) -> [LintingIssue]
}

class StaticProductsGraphLinter: StaticProductsGraphLinting {
    func lint(graph: Graph) -> [LintingIssue] {
        let nodes = graph.entryNodes
        return warnings(in: nodes)
            .sorted()
            .map(lintIssue)
    }

    private func warnings(in nodes: [GraphNode]) -> Set<StaticDependencyWarning> {
        var warnings = Set<StaticDependencyWarning>()
        let cache = Cache()
        nodes.forEach { node in
            // Skip already evaluated nodes
            guard cache.results(for: node) == nil else {
                return
            }
            let results = buildStaticProductsMap(visiting: node,
                                                 cache: cache)
            warnings.formUnion(results.linked.flatMap(staticDependencyWarning))
        }
        return warnings
    }

    ///
    /// Builds a static products map to enable performing some validation/lint checks.
    ///
    /// The map consists of all linked static products as follows:
    /// `StaticProducts.linked`:
    /// - MyStaticFrameworkA > [MyDynamicFrameworkA, MyTestsTarget]
    /// - MyStaticFrameworkB > [MyDynamicFrameworkA, MyTestsTarget]
    ///
    /// The map is constructed by traversing the graph from the given node using
    /// a depth first approach reaching to the leaf nodes. Once there, working
    /// backwards all nodes are evaluated as follows:
    ///
    /// There are two "buckets", `StaticProducts.unlinked` and `StaticProducts.linked`
    ///
    /// - In the event a node is a static product it adds itself to the unlinked bucket
    /// - In the event a node is a node capable of linking static products, it removes all the nodes
    ///   from the unlinked bucket and places them in the linked bucket in format of _staticNode > [linkingNode]_.
    ///
    private func buildStaticProductsMap(visiting node: GraphNode,
                                        cache: Cache) -> StaticProducts
    {
        if let cachedResult = cache.results(for: node) {
            return cachedResult
        }

        // Collect dependency results traversing the graph (dfs)
        var results = dependencies(for: node).reduce(StaticProducts()) { results, node in
            buildStaticProductsMap(visiting: node, cache: cache).merged(with: results)
        }

        // Static node case
        if nodeIsStaticProduct(node) {
            results.unlinked.insert(node)
            cache.cache(results: results, for: node)
            return results
        }

        // Linking node case
        guard let linkingNode = node as? TargetNode,
            linkingNode.target.canLinkStaticProducts()
        else {
            return results
        }

        while let staticProduct = results.unlinked.popFirst() {
            results.linked[staticProduct, default: Set()].insert(linkingNode)
        }

        cache.cache(results: results,
                    for: node)

        return results
    }

    private func staticDependencyWarning(staticProduct: GraphNode,
                                         linkedBy: Set<TargetNode>) -> [StaticDependencyWarning]
    {
        // Common dependencies between test bundles and their host apps are automatically omitted
        // during generation - as such those shouldn't be flagged
        //
        // reference: https://github.com/tuist/tuist/pull/664
        let apps: Set<GraphNode> = linkedBy.filter { $0.target.product == .app }
        let hostedTestBundles = linkedBy
            .filter { $0.target.product.testsBundle }
            .filter { $0.dependencies.contains(where: { apps.contains($0) }) }

        let links = linkedBy.subtracting(hostedTestBundles)

        guard links.count > 1 else {
            return []
        }

        let sortedLinks = links.sorted(by: { $0.name < $1.name })
        return [
            .init(staticProduct: staticProduct,
                  linkingNodes: sortedLinks),
        ]
    }

    private func dependencies(for node: GraphNode) -> [GraphNode] {
        guard let targetNode = node as? TargetNode else {
            return []
        }
        return targetNode.dependencies.filter { canVisit(node: $0, from: targetNode) }
    }

    private func canVisit(node: GraphNode, from: TargetNode) -> Bool {
        guard let to = node as? TargetNode else {
            return true
        }
        switch (from.target.product, to.target.product) {
        case (.uiTests, .app):
            // UITest bundles are hosted in a separate app (App-TestRunner) as such
            // it should be treated as a separate graph that isn't connected to the main
            // app's graph. It's an unfortunate side effect of declaring a target application
            // of a UI test bundle as a dependency.
            return false
        default:
            return true
        }
    }

    private func nodeIsStaticProduct(_ node: GraphNode) -> Bool {
        switch node {
        case is PackageProductNode:
            // Swift package products are currently assumed to be static
            return true
        case is LibraryNode:
            return true
        case let targetNode as TargetNode where targetNode.target.product.isStatic:
            return true
        default:
            return false
        }
    }

    private func lintIssue(from warning: StaticDependencyWarning) -> LintingIssue {
        let staticProduct = nodeDescription(warning.staticProduct)
        let names = warning.linkingNodes.map(\.name)
        return LintingIssue(reason: "\(staticProduct) has been linked against \(names), it is a static product so may introduce unwanted side effects.",
                            severity: .warning)
    }

    private func nodeDescription(_ node: GraphNode) -> String {
        switch node {
        case is PackageProductNode:
            return "Package \"\(node.name)\""
        case is LibraryNode:
            return "Library \"\(node.name)\""
        case is TargetNode:
            return "Target \"\(node.name)\""
        default:
            return node.name
        }
    }
}

// MARK: - Helper Types

extension StaticProductsGraphLinter {
    private struct StaticDependencyWarning: Hashable, Comparable {
        var staticProduct: GraphNode
        var linkingNodes: [TargetNode]

        var debugDescription: String {
            stringDescription
        }

        private var stringDescription: String {
            "\(staticProduct.name) > \(linkingNodes.map(\.name))"
        }

        static func < (lhs: StaticDependencyWarning,
                       rhs: StaticDependencyWarning) -> Bool
        {
            lhs.stringDescription < rhs.stringDescription
        }
    }

    private struct StaticProducts {
        // Unlinked static products
        var unlinked: Set<GraphNode> = Set()

        // Map of Static product to nodes that link it
        // e.g.
        //    - MyStaticFrameworkA > [MyDynamicFrameworkA, MyTestsTarget]
        //    - MyStaticFrameworkB > [MyDynamicFrameworkA, MyTestsTarget]
        var linked: [GraphNode: Set<TargetNode>] = [:]

        func merged(with other: StaticProducts) -> StaticProducts {
            StaticProducts(unlinked: unlinked.union(other.unlinked),
                           linked: linked.merging(other.linked, uniquingKeysWith: { $0.union($1) }))
        }
    }

    private class Cache {
        private var cachedResults: [GraphNode: StaticProducts] = [:]

        func results(for node: GraphNode) -> StaticProducts? {
            cachedResults[node]
        }

        func cache(results: StaticProducts,
                   for node: GraphNode)
        {
            cachedResults[node] = results
        }
    }
}
