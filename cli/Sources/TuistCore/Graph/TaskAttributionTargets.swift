import Foundation
import XcodeGraph

/// The targets whose Swift code can be built with function-entry tracking
/// (`-sanitize-coverage=func,trace-pc-guard,pc-table`), which TestCoverageAttribution uses to tell
/// apart the Swift Testing tests that run in parallel in one process.
///
/// Tracked code calls back into TestCoverageAttribution on every function entry, so every image that
/// links it has to link the package too, or the link fails. Those are the unit test targets that
/// link the package, and the static targets only such test targets link, directly or through other
/// static targets. A static target that an app, a framework, a macro or any other image links is left
/// out. So are the targets of external packages: their files are never evidence, which keeps only the
/// repository's files, and slowing their code down only perturbs it. The package's own targets are
/// left out too. The code left out still counts, through the counters, for every test of the process
/// that ran it.
public enum TaskAttributionTargets {
    /// TestCoverageAttribution's targets, whose code is the attribution itself.
    static let packageTargets: Set<String> = ["TestCoverageAttribution", "TestCoverageAttributionObserver"]

    /// The eligible targets, as `$(TARGET_NAME:c99extidentifier)` writes their names: a build setting
    /// passed to xcodebuild can only tell targets apart by name. A name an ineligible target shares,
    /// in another project or once made an identifier, is left out.
    public static func identifiers(graph: Graph) -> Set<String> {
        let traverser = GraphTraverser(graph: graph)
        var attributing: Set<GraphTarget> = []
        var linkedByAttributing: Set<GraphTarget> = []
        var linkedByOthers: Set<GraphTarget> = []

        for target in traverser.allTargets() where !target.target.product.isStatic {
            let linksPackage = target.target.product == .unitTests && linksTestCoverageAttribution(
                target,
                traverser: traverser,
                graph: graph
            )
            if linksPackage { attributing.insert(target) }
            let linked = traverser.transitiveStaticDependencies(from: .target(name: target.target.name, path: target.path))
                .compactMap { dependency -> GraphTarget? in
                    guard case let .target(name, path, _) = dependency else { return nil }
                    return traverser.target(path: path, name: name)
                }
            if linksPackage {
                linkedByAttributing.formUnion(linked)
            } else {
                linkedByOthers.formUnion(linked)
            }
        }

        let eligible = attributing.union(linkedByAttributing.subtracting(linkedByOthers))
            .filter { !isExternal($0) && !packageTargets.contains($0.target.name) && hasSwiftSources($0.target) }
        let eligibleIdentifiers = Set(eligible.map { identifier($0.target.name) })
        let ineligibleIdentifiers = Set(traverser.allTargets().subtracting(eligible).map { identifier($0.target.name) })
        return eligibleIdentifiers.subtracting(ineligibleIdentifiers)
    }

    /// What Xcode's `c99extidentifier` makes of a name: every character that can't be in a C
    /// identifier becomes an underscore, and a leading digit is preceded by one.
    public static func identifier(_ name: String) -> String {
        let characters = name.unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")) ? Character(scalar) : "_"
        }
        let identifier = String(characters)
        return identifier.first?.isNumber == true ? "_" + identifier : identifier
    }

    private static func linksTestCoverageAttribution(_ target: GraphTarget, traverser: GraphTraverser, graph: Graph) -> Bool {
        if traverser.allTargetDependencies(path: target.path, name: target.target.name)
            .contains(where: { $0.target.name == "TestCoverageAttribution" })
        {
            return true
        }
        return graph.dependencies[.target(name: target.target.name, path: target.path), default: []].contains {
            if case let .packageProduct(_, product, _) = $0 { return product == "TestCoverageAttribution" }
            return false
        }
    }

    private static func isExternal(_ target: GraphTarget) -> Bool {
        if case .external = target.project.type { return true }
        return false
    }

    private static func hasSwiftSources(_ target: Target) -> Bool {
        target.sources.contains { $0.path.extension == "swift" }
            || target.buildableFolders.contains { !$0.resolvedFiles.filter { $0.path.extension == "swift" }.isEmpty }
    }
}
