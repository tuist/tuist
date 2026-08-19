import Foundation
import Path
import TuistAlert
import XcodeGraph

/// Several precompiled artifacts that answer to one framework name on a target's search paths.
struct FrameworkNameAmbiguity: Hashable {
    let name: String
    let paths: [AbsolutePath]
}

/// Answers which framework a precompiled artifact puts on a search path, and finds the artifacts that
/// compete for the same one.
///
/// The name is not the artifact's own: an `.xcframework` container can be named anything, and what a target
/// imports is the framework named by each slice's `LibraryPath`. Those names are read from the graph once,
/// because the per-target search path computation is deliberately cheap and reading them there would put
/// the cost back.
struct FrameworkNameAmbiguityDetector: Sendable {
    private let namesByXCFrameworkPath: [AbsolutePath: Set<String>]

    init(graph: Graph) {
        var namesByPath: [AbsolutePath: Set<String>] = [:]
        func index(_ dependency: GraphDependency) {
            guard case let .xcframework(xcframework) = dependency else { return }
            namesByPath[xcframework.path] = Set(
                xcframework.infoPlist.libraries
                    .filter { $0.path.extension == "framework" }
                    .map(\.binaryName)
            )
        }
        // Both sides of every edge: a leaf artifact is reachable as a value without ever being a key.
        for (dependency, dependencies) in graph.dependencies {
            index(dependency)
            for dependency in dependencies {
                index(dependency)
            }
        }
        namesByXCFrameworkPath = namesByPath
    }

    /// Only an `.xcframework` needs the index: every other artifact is the bundle it is named after, and an
    /// artifact carrying no `.framework` at all, a library slice or a `.a`, resolves through other flags and
    /// answers to no framework name here.
    private func frameworkNames(of path: AbsolutePath) -> Set<String> {
        namesByXCFrameworkPath[path] ?? (path.extension == "framework" ? [path.basenameWithoutExt] : [])
    }

    func ambiguities(among paths: Set<AbsolutePath>) -> [FrameworkNameAmbiguity] {
        var pathsByFrameworkName: [String: [AbsolutePath]] = [:]
        for path in paths {
            for frameworkName in frameworkNames(of: path) {
                pathsByFrameworkName[frameworkName, default: []].append(path)
            }
        }
        return pathsByFrameworkName
            .filter { $0.value.count > 1 }
            .map { FrameworkNameAmbiguity(name: $0.key, paths: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }
}

/// Reports artifacts that compete for one framework name rather than letting the search path order pick
/// between them silently.
///
/// The order is stable wherever the competing artifacts have a machine-independent identity to sort on, but
/// two artifacts both vendored at machine-specific locations have none, so which one a target builds against
/// can differ between machines.
struct FrameworkNameAmbiguityReporter {
    func report(_ ambiguities: [FrameworkNameAmbiguity], targets targetNamesByAmbiguity: [FrameworkNameAmbiguity: [String]]) {
        for ambiguity in ambiguities {
            guard let targetNames = targetNamesByAmbiguity[ambiguity], let firstTargetName = targetNames.first
            else { continue }
            let scope: String
            let verb: String
            switch targetNames.count {
            case 1:
                scope = "The target '\(firstTargetName)'"
                verb = "depends"
            case 2:
                scope = "The target '\(firstTargetName)' and 1 other target"
                verb = "depend"
            default:
                scope = "The target '\(firstTargetName)' and \(targetNames.count - 1) other targets"
                verb = "depend"
            }
            let paths = ambiguity.paths.map(\.pathString).joined(separator: ", ")
            AlertController.current.warning(.alert(
                "\(scope) \(verb) on \(ambiguity.paths.count) precompiled artifacts providing '\(ambiguity.name)': \(paths). Only one of them is resolved through the framework search paths, and which one wins can follow where the artifacts are stored, so another machine can resolve a different one.",
                takeaway: "Depend on a single artifact providing '\(ambiguity.name)' so what a target builds against doesn't depend on where the artifacts are stored."
            ))
        }
    }
}
