import Path
import XcodeGraph

/// The test modules a changed file can affect, for coverage-based test selection: the test targets
/// that depend, directly or not, on a target that owns the file, the owner included when it's a test
/// target. It works on any graph, generated from manifests or mapped from an Xcode project.
///
/// A file no target owns (a README, CI configuration) affects no module. A project-level file the
/// graph can't attribute to one target (an `.xcconfig`, the `.xcodeproj` itself) has no answer:
/// the server's tracked files cover those.
///
/// Paths are compared without macOS's `/private` prefix, which Git reports and XcodeGraphMapper
/// drops: otherwise every changed file would look unowned, and its tests could be skipped.
public struct TestImpactAffectedModules {
    private struct TargetKey: Hashable {
        let path: AbsolutePath
        let name: String
    }

    /// The targets owning a file or folder, keyed by its path.
    private let owners: [AbsolutePath: Set<TargetKey>]
    /// Paths inside a target's buildable folders that the target excludes.
    private let excluded: [AbsolutePath: Set<TargetKey>]
    private let projectLevel: Set<AbsolutePath>
    private let testModulesByTarget: [TargetKey: [String]]

    public init(graph: Graph) {
        var owners: [AbsolutePath: Set<TargetKey>] = [:]
        var excluded: [AbsolutePath: Set<TargetKey>] = [:]
        var projectLevel: Set<AbsolutePath> = []
        var testTargets: [TargetKey: String] = [:]

        for (projectPath, project) in graph.projects {
            projectLevel.insert(Self.canonical(project.xcodeProjPath))
            projectLevel.formUnion(project.settings.configurations.values.compactMap { $0?.xcconfig }.map(Self.canonical))
            for target in project.targets.values {
                let key = TargetKey(path: projectPath, name: target.name)
                if target.product.testsBundle { testTargets[key] = target.name }
                projectLevel
                    .formUnion((target.settings?.configurations.values.compactMap { $0?.xcconfig } ?? []).map(Self.canonical))
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

        var dependents: [TargetKey: Set<TargetKey>] = [:]
        for (dependent, dependencies) in graph.dependencies {
            guard case let .target(name, path, _) = dependent else { continue }
            for case let .target(dependencyName, dependencyPath, _) in dependencies {
                dependents[TargetKey(path: dependencyPath, name: dependencyName), default: []]
                    .insert(TargetKey(path: path, name: name))
            }
        }
        var testModulesByTarget: [TargetKey: [String]] = [:]
        for key in Set(owners.values.joined()) {
            var visited: Set<TargetKey> = [key]
            var stack = [key]
            while let node = stack.popLast() {
                for dependent in dependents[node, default: []] where visited.insert(dependent).inserted {
                    stack.append(dependent)
                }
            }
            testModulesByTarget[key] = Set(visited.compactMap { testTargets[$0] }).sorted()
        }

        self.owners = owners
        self.excluded = excluded
        self.projectLevel = projectLevel
        self.testModulesByTarget = testModulesByTarget
    }

    /// The test modules, sorted, that a change to the file at `path` can affect, or nil when the
    /// file is project-level. Files inside an owned folder, such as an asset catalog, belong to it.
    public func affectedModules(path: AbsolutePath) -> [String]? {
        var ancestors: [AbsolutePath] = [Self.canonical(path)]
        while let parent = ancestors.last?.parentDirectory, parent != ancestors.last {
            ancestors.append(parent)
        }
        if ancestors.contains(where: projectLevel.contains) { return nil }

        let excludedTargets = Set(ancestors.compactMap { excluded[$0] }.joined())
        let owningTargets = Set(ancestors.compactMap { owners[$0] }.joined()).subtracting(excludedTargets)
        return Set(owningTargets.flatMap { testModulesByTarget[$0] ?? [] }).sorted()
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
