import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// Static Products Graph Linter
///
/// A linter that identifies potential issues in a graph where
/// static products are linked multiple times.
///
protocol StaticProductsGraphLinting {
    func lint(graphTraverser: GraphTraversing, config: Config) -> [LintingIssue]
}

class StaticProductsGraphLinter: StaticProductsGraphLinting {
    func lint(graphTraverser: GraphTraversing, config: Config) -> [LintingIssue] {
        warnings(in: Array(graphTraverser.dependencies.keys), graphTraverser: graphTraverser, config: config)
            .sorted()
            .map(lintIssue)
    }

    private func warnings(
        in dependencies: [GraphDependency],
        graphTraverser: GraphTraversing,
        config: Config
    ) -> Set<StaticDependencyWarning> {
        var warnings = Set<StaticDependencyWarning>()
        let cache = Cache()
        for dependency in dependencies {
            // Skip already evaluated nodes
            guard cache.results(for: dependency) == nil else {
                continue
            }
            let results = buildStaticProductsMap(
                visiting: dependency,
                graphTraverser: graphTraverser,
                cache: cache,
                config: config
            )

            warnings.formUnion(results.linked.flatMap {
                staticDependencyWarning(staticProduct: $0.key, linkedBy: $0.value, graphTraverser: graphTraverser, config: config)
            })
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
    private func buildStaticProductsMap(
        visiting dependency: GraphDependency,
        graphTraverser: GraphTraversing,
        cache: Cache,
        config: Config
    ) -> StaticProducts {
        if let cachedResult = cache.results(for: dependency) {
            return cachedResult
        }

        // Collect dependency results traversing the graph (dfs)
        var results = dependencies(for: dependency, graphTraverser: graphTraverser).reduce(StaticProducts()) { results, dep in
            buildStaticProductsMap(visiting: dep, graphTraverser: graphTraverser, cache: cache, config: config)
                .merged(with: results)
        }

        // Static node case
        if isStaticProduct(dependency, graphTraverser: graphTraverser) {
            results.unlinked.insert(dependency)
            cache.cache(results: results, for: dependency)
            return results
        }

        // Linking node case
        guard case let GraphDependency.target(targetName, targetPath) = dependency,
              let dependencyTarget = graphTraverser.target(path: targetPath, name: targetName),
              dependencyTarget.target.canLinkStaticProducts()
        else {
            return results
        }

        while let staticProduct = results.unlinked.popFirst() {
            results.linked[staticProduct, default: Set()].insert(dependency)
        }

        cache.cache(
            results: results,
            for: dependency
        )

        return results
    }

    private func staticDependencyWarning(
        staticProduct: GraphDependency,
        linkedBy: Set<GraphDependency>,
        graphTraverser: GraphTraversing,
        config: Config
    ) -> [StaticDependencyWarning] {
        if shouldSkipDependency(staticProduct, config: config) {
            return []
        }

        // Common dependencies between test bundles and their hosts are automatically omitted
        // during generation - as such those shouldn't be flagged
        //
        // reference: https://github.com/tuist/tuist/pull/664
        let hosts: Set<GraphDependency> = linkedBy.filter { dependency -> Bool in
            guard case let GraphDependency.target(targetName, targetPath) = dependency else { return false }
            guard let target = graphTraverser.target(path: targetPath, name: targetName) else { return false }
            return target.target.product.canHostTests()
        }
        let hostedTestBundles = linkedBy.filter { dependency -> Bool in
            guard case let GraphDependency.target(targetName, targetPath) = dependency else { return false }
            guard let target = graphTraverser.target(path: targetPath, name: targetName) else { return false }

            let isTestsBundle = target.target.product.testsBundle
            let hasHost = dependencies(for: dependency, graphTraverser: graphTraverser).contains(where: { hosts.contains($0) })
            return isTestsBundle && hasHost
        }

        let links = linkedBy.subtracting(hostedTestBundles)

        guard links.count > 1 else {
            return []
        }

        return [
            .init(
                staticProduct: staticProduct,
                linkingDependencies: links.sorted()
            ),
        ]
    }

    private func shouldSkipDependency(_ dependency: GraphDependency, config: Config) -> Bool {
        switch config.generationOptions.staticSideEffectsWarningTargets {
        case .all: return false
        case .none: return true
        case let .excluding(names): return names.contains(dependency.name)
        }
    }

    private func isStaticProduct(_ dependency: GraphDependency, graphTraverser: GraphTraversing) -> Bool {
        switch dependency {
        case let .xcframework(xcframework):
            return xcframework.linking == .static
        case let .framework(_, _, _, _, linking, _, _):
            return linking == .static
        case let .library(_, _, linking, _, _):
            return linking == .static
        case .bundle:
            return true
        case let .packageProduct(_, _, type):
            switch type {
            // Swift package products are currently assumed to be static
            case .runtime: return true
            case .macro: return false
            case .plugin: return false
            }
        case let .target(name, path):
            guard let target = graphTraverser.target(path: path, name: name) else { return false }
            return target.target.product.isStatic
        case .sdk, .macro:
            return false
        }
    }

    private func dependencies(for dependency: GraphDependency, graphTraverser: GraphTraversing) -> [GraphDependency] {
        Array(graphTraverser.dependencies[dependency, default: Set()])
            .filter { canVisit(dependency: $0, from: dependency, graphTraverser: graphTraverser) }
    }

    private func canVisit(dependency: GraphDependency, from: GraphDependency, graphTraverser: GraphTraversing) -> Bool {
        guard case let GraphDependency.target(fromTargetName, fromTargetPath) = from else { return true }
        guard case let GraphDependency.target(toTargetName, toTargetPath) = dependency else { return true }

        guard let fromTarget = graphTraverser.target(path: fromTargetPath, name: fromTargetName) else { return false }
        guard let toTarget = graphTraverser.target(path: toTargetPath, name: toTargetName) else { return false }

        switch (fromTarget.target.product, toTarget.target.product) {
        case (.uiTests, .app):
            // UITest bundles are hosted in a separate app (App-TestRunner) as such
            // it should be treated as a separate graph that isn't connected to the main
            // app's graph. It's an unfortunate side effect of declaring a target application
            // of a UI test bundle as a dependency.
            return false
        case (.app, .appExtension):
            // App Extensions can safely link the same static products as apps
            // as they are an independent product
            return false
        case (.app, .watch2App):
            // Watch Apps (and their extension) can safely link the same static products as apps
            // as they are an independent product
            return false
        case (.app, .appClip):
            // App Clips can safely link the same static products as apps
            // as they are an independent product
            return false
        case (.app, .messagesExtension):
            // Message Extensions can safely link the same static products as apps
            // as they are an independent product
            return false
        case (.app, .extensionKitExtension):
            // ExtensionKit extensions can safely link the same static products as apps
            // as they are an independent product
            return false
        case (.app, .app), (.app, .commandLineTool):
            // macOS application target can embed other helper applications, those helper applications
            // can safely link the same static products as they are independent products
            return false
        case (.app, .systemExtension):
            // System Extension can safely link the same static products as apps
            // as they are an independent product
            return false
        default:
            return true
        }
    }

    private func lintIssue(from warning: StaticDependencyWarning) -> LintingIssue {
        let names = warning.linkingDependencies.map(\.description).listed()
        return LintingIssue(
            reason: "\(warning.staticProduct) has been linked from \(names), it is a static product so may introduce unwanted side effects."
                .uppercasingFirst,
            severity: .warning
        )
    }
}

// MARK: - Helper Types

extension StaticProductsGraphLinter {
    private struct StaticDependencyWarning: Hashable, Comparable {
        var staticProduct: GraphDependency
        var linkingDependencies: [GraphDependency]

        var debugDescription: String {
            stringDescription
        }

        private var stringDescription: String {
            "\(staticProduct) > \(linkingDependencies.map(\.description))"
        }

        static func < (
            lhs: StaticDependencyWarning,
            rhs: StaticDependencyWarning
        ) -> Bool {
            lhs.stringDescription < rhs.stringDescription
        }
    }

    private struct StaticProducts {
        // Unlinked static products
        var unlinked: Set<GraphDependency> = Set()

        // Map of Static product to nodes that link it
        // e.g.
        //    - MyStaticFrameworkA > [MyDynamicFrameworkA, MyTestsTarget]
        //    - MyStaticFrameworkB > [MyDynamicFrameworkA, MyTestsTarget]
        var linked: [GraphDependency: Set<GraphDependency>] = [:]

        func merged(with other: StaticProducts) -> StaticProducts {
            StaticProducts(
                unlinked: unlinked.union(other.unlinked),
                linked: linked.merging(other.linked, uniquingKeysWith: { $0.union($1) })
            )
        }
    }

    private class Cache {
        private var cachedResults: [GraphDependency: StaticProducts] = [:]

        func results(for dependency: GraphDependency) -> StaticProducts? {
            cachedResults[dependency]
        }

        func cache(
            results: StaticProducts,
            for dependency: GraphDependency
        ) {
            cachedResults[dependency] = results
        }
    }
}
