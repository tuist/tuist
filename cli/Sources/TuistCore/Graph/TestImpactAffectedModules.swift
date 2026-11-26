import Path
import XcodeGraph

/// The test modules a changed file is test code of, for coverage-based test selection: the test
/// targets that own it. The server never skips whole a module that gained a file, so a test a new
/// file adds runs; any other change selects through the tests' coverage evidence, or the tracked
/// files. It works on any graph, generated from manifests or mapped from an Xcode project.
///
/// A file no test target owns (a source of a framework, a README, an `.xcconfig`) is no module's.
///
/// Paths are compared without macOS's `/private` prefix, which Git reports and XcodeGraphMapper
/// drops: otherwise a new test file would look unowned, and its module could be skipped whole.
public struct TestImpactAffectedModules {
    private struct TargetKey: Hashable {
        let path: AbsolutePath
        let name: String
    }

    /// The test targets owning a file or folder, keyed by its path.
    private let owners: [AbsolutePath: Set<TargetKey>]
    /// Paths inside a target's buildable folders that the target excludes.
    private let excluded: [AbsolutePath: Set<TargetKey>]

    public init(graph: Graph) {
        var owners: [AbsolutePath: Set<TargetKey>] = [:]
        var excluded: [AbsolutePath: Set<TargetKey>] = [:]

        for (projectPath, project) in graph.projects {
            for target in project.targets.values where target.product.testsBundle {
                let key = TargetKey(path: projectPath, name: target.name)
                for path in Self.ownedPaths(target) {
                    owners[Self.canonical(path), default: []].insert(key)
                }
                for folder in target.buildableFolders {
                    owners[Self.canonical(folder.path), default: []].insert(key)
                    for path in folder.exceptions.exceptions.flatMap(\.excluded) {
                        excluded[Self.canonical(path), default: []].insert(key)
                    }
                }
            }
        }

        self.owners = owners
        self.excluded = excluded
    }

    /// The test modules, sorted, whose test code the file at `path` is. Files inside an owned
    /// folder, such as an asset catalog, belong to it.
    public func affectedModules(path: AbsolutePath) -> [String] {
        var ancestors: [AbsolutePath] = [Self.canonical(path)]
        while let parent = ancestors.last?.parentDirectory, parent != ancestors.last {
            ancestors.append(parent)
        }

        let excludedTargets = Set(ancestors.compactMap { excluded[$0] }.joined())
        let owningTargets = Set(ancestors.compactMap { owners[$0] }.joined()).subtracting(excludedTargets)
        return Set(owningTargets.map(\.name)).sorted()
    }

    /// The path without the `/private` that macOS's `/var`, `/tmp` and `/etc` resolve through. It
    /// doesn't consult the file system, so a deleted file's path maps like an existing one's.
    private static func canonical(_ path: AbsolutePath) -> AbsolutePath {
        let string = path.pathString
        for directory in ["/private/var", "/private/tmp", "/private/etc"]
            where string == directory || string.hasPrefix(directory + "/")
        {
            return (try? AbsolutePath(validating: String(string.dropFirst("/private".count)))) ?? path
        }
        return path
    }

    /// The files and folders a target builds or bundles, apart from its buildable folders.
    private static func ownedPaths(_ target: Target) -> [AbsolutePath] {
        var paths = target.sources.map(\.path)
        paths += target.resources.resources.map(\.path)
        paths += target.copyFiles.flatMap(\.files).compactMap(\.path)
        paths += target.coreDataModels.map(\.path)
        paths += target.playgrounds
        if let headers = target.headers {
            paths += headers.public + headers.private + headers.project
        }
        paths += [target.infoPlist?.path, target.entitlements?.path].compactMap { $0 }
        return paths
    }
}
