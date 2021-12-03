import Foundation
import TuistGraph

extension Project {
    /// It returns the project targets sorted based on the target type and the dependencies between them.
    /// The most dependent and non-tests targets are sorted first in the list.
    ///
    /// - Parameter graph: Dependencies graph.
    /// - Returns: Sorted targets.
    public func sortedTargetsForProjectScheme(graph: Graph) -> [Target] {
        targets.sorted { first, second -> Bool in
            // First criteria: Test bundles at the end
            if first.product.testsBundle, !second.product.testsBundle {
                return false
            }
            if !first.product.testsBundle, second.product.testsBundle {
                return true
            }

            let graphTraverser = GraphTraverser(graph: graph)

            // Second criteria: Most dependent targets first.
            let secondDependencies = graphTraverser.directTargetDependencies(path: self.path, name: second.name)
                .filter { $0.path == self.path }
                .map(\.target.name)
            let firstDependencies = graphTraverser.directTargetDependencies(path: self.path, name: first.name)
                .filter { $0.path == self.path }
                .map(\.target.name)

            if secondDependencies.contains(first.name) {
                return true
            } else if firstDependencies.contains(second.name) {
                return false

                // Third criteria: Name
            } else {
                return first.name < second.name
            }
        }
    }
}
