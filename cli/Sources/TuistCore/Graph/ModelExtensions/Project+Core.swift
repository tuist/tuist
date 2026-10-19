import Path
import TuistConstants
import TuistSupport
import XcodeGraph

extension Project {
    /// Whether the project's code is the repository's own: a project of the workspace, or a package the
    /// manifest references by path, which resolves without a hash. A package resolved from source control
    /// or a registry carries the hash of that resolution and lives outside the repository. This is the
    /// rule the server applies to a reported target (`external_hash` empty), so coverage judges the two
    /// alike.
    public var isRepositoryOwned: Bool {
        switch type {
        case .local: return true
        case let .external(hash): return hash == nil
        }
    }

    /// It returns the project targets sorted based on the target type and the dependencies between them.
    /// The most dependent and non-tests targets are sorted first in the list.
    ///
    /// - Parameter graph: Dependencies graph.
    /// - Returns: Sorted targets.
    public func sortedTargetsForProjectScheme(graph: Graph) -> [Target] {
        targets.values.sorted { first, second -> Bool in
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
                .filter { $0.graphTarget.path == self.path }
                .map(\.target.name)
            let firstDependencies = graphTraverser.directTargetDependencies(path: self.path, name: first.name)
                .filter { $0.graphTarget.path == self.path }
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

    public func derivedDirectoryPath(for target: Target) -> AbsolutePath {
        let resolvedSwiftPackageManagerScratchDirectory = SwiftPackageManagerPaths.scratchDirectory(
            containingPackageSource: path,
            knownScratchDirectory: swiftPackageManagerScratchDirectory
        )
        if case .external = type,
           let resolvedSwiftPackageManagerScratchDirectory,
           SwiftPackageManagerPaths.isPath(path, inPackageSourcesOf: resolvedSwiftPackageManagerScratchDirectory)
        {
            return resolvedSwiftPackageManagerScratchDirectory
                .appending(
                    components: [
                        Constants.DerivedDirectory.dependenciesDerivedDirectory,
                        Constants.DerivedDirectory.dependenciesTargetDirectory,
                        target.name,
                    ]
                )
        } else {
            return path
                .appending(
                    component: Constants.DerivedDirectory.name
                )
        }
    }
}
