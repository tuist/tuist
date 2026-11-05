import Foundation
import TuistConfig
import TuistCore
import XcodeGraph

/// Static Products Graph Linter
///
/// A linter that identifies potential issues in a graph where
/// static products are linked multiple times.
protocol StaticProductsGraphLinting {
    func lint(graphTraverser: GraphTraversing, configGeneratedProjectOptions: TuistGeneratedProjectOptions) -> [LintingIssue]
}

struct StaticProductsGraphLinter: StaticProductsGraphLinting {
    func lint(graphTraverser: GraphTraversing, configGeneratedProjectOptions: TuistGeneratedProjectOptions) -> [LintingIssue] {
        if case .none = configGeneratedProjectOptions.generationOptions.staticSideEffectsWarningTargets {
            return []
        }
        let nodes = Nodes(graphTraverser: graphTraverser)
        return warnings(
            nodes: nodes,
            graphTraverser: graphTraverser,
            configGeneratedProjectOptions: configGeneratedProjectOptions
        )
        // Comparing descriptions directly would rebuild both strings on every comparison.
        .map { (description: nodes.description(of: $0), warning: $0) }
        .sorted { $0.description < $1.description }
        .map { lintIssue(from: $0.warning, nodes: nodes) }
    }

    private func warnings(
        nodes: Nodes,
        graphTraverser: GraphTraversing,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    ) -> Set<StaticDependencyWarning> {
        var warnings = Set<StaticDependencyWarning>()
        var cache = [StaticProducts?](repeating: nil, count: nodes.count)
        var active = [Bool](repeating: false, count: nodes.count)
        for root in nodes.roots {
            // Skip already evaluated nodes
            guard cache[root] == nil else {
                continue
            }
            let results = buildStaticProductsMap(visiting: root, nodes: nodes, cache: &cache, active: &active)

            for (staticProduct, linkedBy) in results.linked {
                if let warning = staticDependencyWarning(
                    staticProduct: staticProduct,
                    linkedBy: linkedBy,
                    nodes: nodes,
                    graphTraverser: graphTraverser,
                    configGeneratedProjectOptions: configGeneratedProjectOptions
                ) {
                    warnings.insert(warning)
                }
            }
        }
        return warnings
    }

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
    private func buildStaticProductsMap(
        visiting node: Int,
        nodes: Nodes,
        cache: inout [StaticProducts?],
        active: inout [Bool]
    ) -> StaticProducts {
        if let cachedResult = cache[node] {
            return cachedResult
        }

        var stack = [StaticProductsFrame(node: node, nextChildIndex: 0, results: StaticProducts())]
        active[node] = true

        while let frame = stack.last {
            let frameIndex = stack.count - 1
            let children = nodes.children[frame.node]
            if frame.nextChildIndex < children.count {
                let child = children[frame.nextChildIndex]

                if let cachedResult = cache[child] {
                    stack[frameIndex].nextChildIndex += 1
                    stack[frameIndex].results.merge(cachedResult)
                    continue
                }

                if active[child] {
                    stack[frameIndex].nextChildIndex += 1
                    continue
                }

                active[child] = true
                stack.append(StaticProductsFrame(node: child, nextChildIndex: 0, results: StaticProducts()))
            } else {
                var completedFrame = stack.removeLast()
                finalize(results: &completedFrame.results, for: completedFrame.node, nodes: nodes)
                cache[completedFrame.node] = completedFrame.results
                active[completedFrame.node] = false

                if let parentFrameIndex = stack.indices.last {
                    stack[parentFrameIndex].nextChildIndex += 1
                    stack[parentFrameIndex].results.merge(completedFrame.results)
                } else {
                    return completedFrame.results
                }
            }
        }

        return cache[node] ?? StaticProducts()
    }

    private func finalize(results: inout StaticProducts, for node: Int, nodes: Nodes) {
        // Static node case
        if nodes.isStaticProduct[node] {
            results.unlinked.insert(node)
            return
        }

        // Linking node case
        guard nodes.canLinkStaticProducts[node] else { return }

        for staticProduct in results.unlinked {
            results.linked[staticProduct, default: Set()].insert(node)
        }
        results.unlinked.removeAll()
    }

    private func staticDependencyWarning(
        staticProduct: Int,
        linkedBy: Set<Int>,
        nodes: Nodes,
        graphTraverser: GraphTraversing,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    ) -> StaticDependencyWarning? {
        guard linkedBy.count > 1 else { return nil }

        if shouldSkipDependency(nodes.dependencies[staticProduct], configGeneratedProjectOptions: configGeneratedProjectOptions) {
            return nil
        }

        // Statically linking a macro does not present a problem so it should not be flagged
        if nodes.hasDirectSwiftMacroExecutables(staticProduct, graphTraverser: graphTraverser) {
            return nil
        }

        // Common dependencies between test bundles and their hosts are automatically omitted
        // during generation - as such those shouldn't be flagged
        //
        // reference: https://github.com/tuist/tuist/pull/664
        let hosts = linkedBy.filter { nodes.products[$0]?.canHostTests() == true }
        let hostedTestBundles = linkedBy.filter { node in
            guard nodes.products[node]?.testsBundle == true else { return false }
            return nodes.children[node].contains(where: hosts.contains)
        }

        let links = linkedBy.subtracting(hostedTestBundles)

        guard links.count > 1 else {
            return nil
        }

        return StaticDependencyWarning(
            staticProduct: staticProduct,
            linkingDependencies: links.sorted { (nodes.descriptions[$0], $0) < (nodes.descriptions[$1], $1) }
        )
    }

    private func shouldSkipDependency(
        _ dependency: GraphDependency,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    ) -> Bool {
        switch configGeneratedProjectOptions.generationOptions.staticSideEffectsWarningTargets {
        case .all: return false
        case .none: return true
        case let .excluding(names): return names.contains(dependency.name)
        }
    }

    private static func isStaticProduct(_ dependency: GraphDependency, target: GraphTarget?) -> Bool {
        switch dependency {
        case let .foreignBuildOutput(output):
            return output.linking == .static
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
            // Preserve the static assumption for products without a linkage hint.
            case .runtime: return true
            case .runtimeEmbedded: return true
            case .runtimeDynamic, .runtimeDynamicEmbedded: return false
            case .macro: return false
            case .plugin: return false
            }
        case .target:
            return target?.target.product.isStatic ?? false
        case .sdk, .macro:
            return false
        }
    }

    private static func canVisit(from: GraphDependency, fromProduct: Product?, to: GraphDependency, toProduct: Product?) -> Bool {
        guard case .target = from else { return true }
        guard case .target = to else { return true }

        guard let fromProduct, let toProduct else { return false }

        switch (fromProduct, toProduct) {
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
        case (.app, .watch2App), (.watch2AppContainer, .watch2App):
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
        case (.app, .app), (.app, .commandLineTool), (.app, .xpc):
            // macOS application target can embed other helper applications, those helper applications
            // can safely link the same static products as they are independent products
            return false
        case (.app, .systemExtension):
            // System Extension can safely link the same static products as apps
            // as they are an independent product
            return false
        case (_, .macro):
            // Macro executables can safely link the same static products as the targets
            // depending on the executable's parent target (e.g. framework or library).
            return false
        default:
            return true
        }
    }

    private func lintIssue(from warning: StaticDependencyWarning, nodes: Nodes) -> LintingIssue {
        let names = warning.linkingDependencies.map { nodes.descriptions[$0] }.listed()
        return LintingIssue(
            reason: "\(nodes.descriptions[warning.staticProduct]) has been linked from \(names), it is a static product so may introduce unwanted side effects."
                .uppercasingFirst,
            severity: .warning,
            category: .staticSideEffects
        )
    }

    // MARK: - Helper Types

    /// The graph's dependencies numbered once, together with everything the lint reads about them.
    ///
    /// The traversal merges large sets of static products and their linking nodes at every edge. Working with
    /// integers rather than `GraphDependency` values, whose hashing walks names and paths, and resolving each
    /// target once rather than on every visit, keeps that merging cheap.
    private final class Nodes {
        let dependencies: [GraphDependency]
        /// The graph's dependency keys, in the order the graph iterates them.
        let roots: [Int]
        /// Each node's visitable dependencies, in the order the graph iterates them.
        let children: [[Int]]
        let products: [Product?]
        let isStaticProduct: [Bool]
        let canLinkStaticProducts: [Bool]
        let descriptions: [String]
        private let debugDescriptions: [String]
        private var hasDirectSwiftMacroExecutables: [Bool?]

        var count: Int { dependencies.count }

        init(graphTraverser: GraphTraversing) {
            let graphDependencies = graphTraverser.dependencies
            var dependencies: [GraphDependency] = []
            var ids: [GraphDependency: Int] = [:]
            func id(of dependency: GraphDependency) -> Int {
                if let id = ids[dependency] { return id }
                ids[dependency] = dependencies.count
                dependencies.append(dependency)
                return dependencies.count - 1
            }

            roots = graphDependencies.keys.map { id(of: $0) }
            let edges = graphDependencies.map { dependency, children in (id(of: dependency), Array(children)) }
            for (_, children) in edges {
                for child in children {
                    _ = id(of: child)
                }
            }

            let targets = dependencies.map { dependency -> GraphTarget? in
                guard case let .target(name, path, _) = dependency else { return nil }
                return graphTraverser.target(path: path, name: name)
            }
            let products = targets.map { $0?.target.product }

            var children = [[Int]](repeating: [], count: dependencies.count)
            for (node, nodeChildren) in edges {
                children[node] = nodeChildren.compactMap { child in
                    let childID = ids[child]!
                    return StaticProductsGraphLinter.canVisit(
                        from: dependencies[node],
                        fromProduct: products[node],
                        to: child,
                        toProduct: products[childID]
                    ) ? childID : nil
                }
            }

            self.dependencies = dependencies
            self.children = children
            self.products = products
            isStaticProduct = zip(dependencies, targets).map { StaticProductsGraphLinter.isStaticProduct($0, target: $1) }
            canLinkStaticProducts = targets.map { $0?.target.canLinkStaticProducts() ?? false }
            descriptions = dependencies.map(\.description)
            debugDescriptions = descriptions.map(\.debugDescription)
            hasDirectSwiftMacroExecutables = Array(repeating: nil, count: dependencies.count)
        }

        func hasDirectSwiftMacroExecutables(_ node: Int, graphTraverser: GraphTraversing) -> Bool {
            if let cached = hasDirectSwiftMacroExecutables[node] { return cached }
            var result = false
            if case let .target(name, path, _) = dependencies[node] {
                result = !graphTraverser.directSwiftMacroExecutables(path: path, name: name).isEmpty
            }
            hasDirectSwiftMacroExecutables[node] = result
            return result
        }

        /// The same text as `"\(staticProduct) > \(linkingDependencies.map(\.description))"`, which orders the warnings.
        func description(of warning: StaticDependencyWarning) -> String {
            let linking = warning.linkingDependencies.map { debugDescriptions[$0] }.joined(separator: ", ")
            return "\(descriptions[warning.staticProduct]) > [\(linking)]"
        }
    }

    private struct StaticProductsFrame {
        let node: Int
        var nextChildIndex: Int
        var results: StaticProducts
    }

    private struct StaticDependencyWarning: Hashable {
        var staticProduct: Int
        var linkingDependencies: [Int]
    }

    private struct StaticProducts {
        /// Unlinked static products
        var unlinked: Set<Int> = Set()

        /// Map of static product to nodes that link it
        /// e.g.
        ///    - MyStaticFrameworkA > [MyDynamicFrameworkA, MyTestsTarget]
        ///    - MyStaticFrameworkB > [MyDynamicFrameworkA, MyTestsTarget]
        var linked: [Int: Set<Int>] = [:]

        /// Merges in place: the accumulator is usually uniquely owned, and adopting `other` wholesale when
        /// the accumulator is still empty shares its storage instead of copying it.
        mutating func merge(_ other: StaticProducts) {
            if unlinked.isEmpty { unlinked = other.unlinked } else { unlinked.formUnion(other.unlinked) }
            if linked.isEmpty {
                linked = other.linked
                return
            }
            for (staticProduct, linkingDependencies) in other.linked {
                if let index = linked.index(forKey: staticProduct) {
                    linked.values[index].formUnion(linkingDependencies)
                } else {
                    linked[staticProduct] = linkingDependencies
                }
            }
        }
    }
}
