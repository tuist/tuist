import Foundation
import Path
import TuistAlert
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLogging
import TuistSupport
import XcodeGraph

/// Sets up framework search paths for every target: it derives the precompiled and SDK framework
/// search paths from the target's dependency graph, writes the corresponding build settings onto
/// the target, and — for targets above the consolidation threshold — writes the
/// `Derived/FrameworkSearchPaths/<Target>.resp` response file those settings reference.
///
/// It must run after the binary-cache replacement mappers so it sees the precompiled xcframework
/// dependencies, and its `.resp` side effect must land in the same batch as
/// `DeleteDerivedDirectoryProjectMapper`'s cleanup, after the deletes, so the file is not removed
/// once written — the same way `ModuleMapMapper` writes the dependency module maps.
public struct FrameworkSearchPathsGraphMapper: GraphMapping {
    /// Targets with at least this many unique precompiled framework search paths get those paths
    /// consolidated into a response file to keep C, Objective-C, and linking command lines short.
    private static let consolidationThreshold = 20

    private static let frameworkSearchPathsSetting = "FRAMEWORK_SEARCH_PATHS"
    private static let otherCFlagsSetting = "OTHER_CFLAGS"
    private static let otherSwiftFlagsSetting = "OTHER_SWIFT_FLAGS"
    private static let otherLinkerFlagsSetting = "OTHER_LDFLAGS"

    private struct TargetID: Hashable, Comparable, Sendable {
        let projectPath: AbsolutePath
        let targetName: String

        static func < (lhs: TargetID, rhs: TargetID) -> Bool {
            (lhs.projectPath, lhs.targetName) < (rhs.projectPath, rhs.targetName)
        }
    }

    /// The per-target inputs the search path computation needs, hoisted out of the graph so targets can be
    /// processed independently of one another.
    private struct TargetInput: Sendable {
        let id: TargetID
        let sourceRootPath: AbsolutePath
        let responseFileDirectory: AbsolutePath
    }

    /// Everything one target contributes, accumulated into the graph-wide state once every target has been
    /// processed. The defaults describe a target below the consolidation threshold, which only contributes
    /// build settings.
    private struct TargetOutput {
        let id: TargetID
        let responseFileDirectory: AbsolutePath
        let additions: [(key: String, values: [String])]
        let ambiguities: [FrameworkNameAmbiguity]
        var responseFile: FileDescriptor?
        /// Non-nil for targets that went through consolidation, including when the set is empty: the cleanup
        /// directory has to be registered either way so links left by earlier Tuist versions are still removed.
        var frameworkLinkPaths: Set<AbsolutePath>?
        var symbolicLinks: [SideEffectDescriptor] = []
    }

    private struct PrecompiledArtifact: Hashable {
        let path: AbsolutePath

        var searchPath: LinkGeneratorPath {
            .absolutePath(path.removingLastComponent())
        }

        /// Whether the artifact can be represented by a symbolic link in the consolidated Swift
        /// framework search directory.
        ///
        /// Only single-slice `.framework` artifacts qualify. `.xcframework` artifacts are kept inline:
        /// Swift's `-F` flag doesn't resolve `.xcframework` bundles (they're resolved by Xcode through
        /// the project file references), and symlinking one exposes every platform slice to Xcode's
        /// resource processing, which on some Xcode versions walks the linked bundle as a plain folder
        /// and emits conflicting "Multiple commands produce" copy commands for the per-slice resources.
        var canBeLinkedIntoSwiftSearchPath: Bool {
            path.extension == "framework"
        }
    }

    /// Where a search path sits in the emitted list. `identity` is what makes the order the same on every
    /// machine; `value` is the string that ends up in the build setting, and breaks ties.
    private struct SearchPathOrder: Comparable {
        let rank: Int
        let identity: String
        let value: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.rank, lhs.identity, lhs.value) < (rhs.rank, rhs.identity, rhs.value)
        }
    }

    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        Logger.current.debug("Transforming graph \(graph.name): Setting up framework search paths")

        let graphTraverser = GraphTraverser(graph: graph)

        var generatedResponseFileDirectories: Set<AbsolutePath> = []
        var targetInputs: [TargetInput] = []

        for (_, project) in graph.projects {
            let responseFileDirectory = project.sourceRootPath.appending(
                components: Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.frameworkSearchPaths
            )
            // Registered for every project, including those that end up contributing no response file, so the
            // cleanup descriptor still removes files left behind by a previous generation.
            generatedResponseFileDirectories.insert(responseFileDirectory)

            for (_, target) in project.targets {
                targetInputs.append(
                    TargetInput(
                        id: TargetID(projectPath: project.path, targetName: target.name),
                        sourceRootPath: project.sourceRootPath,
                        responseFileDirectory: responseFileDirectory
                    )
                )
            }
        }

        let ambiguityDetector = FrameworkNameAmbiguityDetector(graph: graph)
        // Read here rather than inside the concurrent map: `Environment.current` is a task local, and the
        // concurrent map runs its iterations outside the current task.
        let cacheDirectory = Environment.current.cacheDirectory

        // Each target's search paths depend only on the (immutable) graph, so they are computed concurrently.
        // This is the dominant cost of a binary-cache generation, and it runs twice: once over the unfocused
        // source graph to derive stable cache hashes, and again after binary substitution.
        //
        // The inputs are sorted because `graph.projects` and `project.targets` iterate in dictionary order, and
        // the concurrent map preserves the order it is given: sorting here is what makes the emitted side
        // effects come out the same on every run.
        let outputs = try targetInputs
            .sorted { $0.id < $1.id }
            .map(context: .concurrent) {
                try targetOutput(
                    for: $0,
                    graphTraverser: graphTraverser,
                    ambiguityDetector: ambiguityDetector,
                    cacheDirectory: cacheDirectory
                )
            }
            .compactMap { $0 }

        var settingsByTarget: [TargetID: [(key: String, values: [String])]] = [:]
        var generatedFileSideEffects: [SideEffectDescriptor] = []
        var generatedSymbolicLinkSideEffects: [SideEffectDescriptor] = []
        var activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var activeFrameworkLinksByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var ambiguities: [FrameworkNameAmbiguity] = []
        var targetNamesByAmbiguity: [FrameworkNameAmbiguity: [String]] = [:]

        for output in outputs {
            settingsByTarget[output.id] = output.additions
            for ambiguity in output.ambiguities {
                if targetNamesByAmbiguity[ambiguity] == nil {
                    ambiguities.append(ambiguity)
                }
                targetNamesByAmbiguity[ambiguity, default: []].append(output.id.targetName)
            }
            if let responseFile = output.responseFile {
                activeFilesByDirectory[output.responseFileDirectory, default: []].insert(responseFile.path)
                generatedFileSideEffects.append(.file(responseFile))
            }
            if let frameworkLinkPaths = output.frameworkLinkPaths {
                activeFrameworkLinksByDirectory[output.responseFileDirectory, default: []]
                    .formUnion(frameworkLinkPaths)
            }
            generatedSymbolicLinkSideEffects.append(contentsOf: output.symbolicLinks)
        }

        FrameworkNameAmbiguityReporter().report(ambiguities, targets: targetNamesByAmbiguity)

        var graph = graph
        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.map { targetName, target in
                guard let additions = settingsByTarget[TargetID(projectPath: project.path, targetName: target.name)]
                else { return (targetName, target) }
                var target = target
                target.settings = apply(additions, to: target.settings, defaultSettings: project.settings.defaultSettings)
                return (target.name, target)
            })
            return (projectPath, project)
        })

        var sideEffects: [SideEffectDescriptor] = generatedResponseFileDirectories.isEmpty ? [] : [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: generatedResponseFileDirectories,
                    activeFilesByDirectory: activeFilesByDirectory,
                    include: ["*.resp"]
                )
            ),
        ]
        if !activeFrameworkLinksByDirectory.isEmpty {
            sideEffects.append(
                .generatedFilesCleanup(
                    GeneratedFilesCleanupDescriptor(
                        directories: Set(activeFrameworkLinksByDirectory.keys),
                        activeFilesByDirectory: activeFrameworkLinksByDirectory,
                        include: ["Swift/*/*.framework", "Swift/*/*.xcframework"]
                    )
                )
            )
        }
        sideEffects.append(contentsOf: generatedFileSideEffects)
        sideEffects.append(contentsOf: generatedSymbolicLinkSideEffects)
        return (graph, sideEffects, environment)
    }

    private func targetOutput(
        for input: TargetInput,
        graphTraverser: GraphTraverser,
        ambiguityDetector: FrameworkNameAmbiguityDetector,
        cacheDirectory: AbsolutePath
    ) throws -> TargetOutput? {
        // `precompiledSearchPathDependencies` rather than `searchablePathDependencies`: the latter builds a
        // `GraphDependencyReference` for every dependency reachable from the target, and everything below
        // reduces those to artifact paths and SDK search paths. On a binary-cache-substituted graph that is
        // hundreds of references per target materialized to be discarded. The two are held in agreement by
        // `PrecompiledSearchPathsDifferentialTests`.
        let searchPathDependencies = graphTraverser
            .precompiledSearchPathDependencies(path: input.id.projectPath, name: input.id.targetName)

        let precompiledArtifacts = Set(searchPathDependencies.precompiledPaths.map(PrecompiledArtifact.init))
        let precompiledPaths = Set(precompiledArtifacts.map(\.searchPath))
        let sdkPaths = Set(searchPathDependencies.sdkSearchPaths.map { LinkGeneratorPath.string($0) })

        guard !precompiledPaths.isEmpty || !sdkPaths.isEmpty else { return nil }

        let ambiguities = ambiguityDetector.ambiguities(among: searchPathDependencies.precompiledPaths)

        var additions: [(key: String, values: [String])] = []
        guard precompiledPaths.count >= Self.consolidationThreshold else {
            additions.append((
                Self.frameworkSearchPathsSetting,
                xcodeValues(
                    of: precompiledPaths.union(sdkPaths),
                    sourceRootPath: input.sourceRootPath,
                    cacheDirectory: cacheDirectory
                )
            ))
            return TargetOutput(
                id: input.id,
                responseFileDirectory: input.responseFileDirectory,
                additions: additions,
                ambiguities: ambiguities
            )
        }

        let responseFilePath = input.responseFileDirectory.appending(component: "\(input.id.targetName).resp")
        let precompiledXcodeValues = xcodeValues(
            of: precompiledPaths,
            sourceRootPath: input.sourceRootPath,
            cacheDirectory: cacheDirectory
        )
        // The response file must contain absolute paths since clang doesn't expand build
        // setting variables. Convert $(SRCROOT)/... to absolute paths.
        let responseFileContents = precompiledXcodeValues
            .map { "-F" + $0.replacingOccurrences(of: "$(SRCROOT)", with: input.sourceRootPath.pathString) }
            .joined(separator: "\n")
            + "\n"

        let responseFileReference = "\"@$(SRCROOT)/\(responseFilePath.relative(to: input.sourceRootPath))\""
        let swiftFrameworkSearchPath = input.responseFileDirectory.appending(
            components: "Swift",
            input.id.targetName
        )
        let swiftSearchPaths = swiftSearchPathValues(
            precompiledArtifacts: precompiledArtifacts,
            swiftFrameworkSearchPath: swiftFrameworkSearchPath,
            sourceRootPath: input.sourceRootPath,
            cacheDirectory: cacheDirectory
        )
        // FRAMEWORK_SEARCH_PATHS keeps only platform framework paths; Clang and the linker read the
        // precompiled paths from the response file via @file to keep command lines short.
        additions.append((
            Self.frameworkSearchPathsSetting,
            xcodeValues(of: sdkPaths, sourceRootPath: input.sourceRootPath, cacheDirectory: cacheDirectory)
        ))
        additions.append((Self.otherCFlagsSetting, [responseFileReference]))
        // OTHER_SWIFT_FLAGS gets -F flags instead of @file because the Xcode 26 ClangImporter and
        // integrated SwiftDriver mishandle a @file token. Each search path is quoted so paths
        // that contain whitespace (e.g. a target named "Notification Service") stay a single
        // token instead of being word-split into an unexpected input file.
        additions.append((Self.otherSwiftFlagsSetting, swiftSearchPaths.values.flatMap { ["-F", "\"\($0)\""] }))
        additions.append((Self.otherLinkerFlagsSetting, [responseFileReference]))

        return TargetOutput(
            id: input.id,
            responseFileDirectory: input.responseFileDirectory,
            additions: additions,
            ambiguities: ambiguities,
            responseFile: FileDescriptor(path: responseFilePath, contents: Data(responseFileContents.utf8)),
            frameworkLinkPaths: swiftSearchPaths.linkPaths,
            symbolicLinks: swiftSearchPaths.symbolicLinks
        )
    }

    private func xcodeValues(
        of paths: Set<LinkGeneratorPath>,
        sourceRootPath: AbsolutePath,
        cacheDirectory: AbsolutePath
    ) -> [String] {
        var ordersByValue: [String: SearchPathOrder] = [:]
        for path in paths {
            let order = searchPathOrder(for: path, sourceRootPath: sourceRootPath, cacheDirectory: cacheDirectory)
            // Distinct paths can render to one value, so keep the lower order: the result must not depend on
            // which of them the set happened to iterate first.
            if let existing = ordersByValue[order.value], existing < order { continue }
            ordersByValue[order.value] = order
        }
        return ordersByValue.values.sorted().map(\.value)
    }

    /// Orders one search path by an identity that stays put across machines.
    ///
    /// Ordering by the rendered value lets a machine-specific directory decide precedence: the value of a
    /// path outside the source root carries the directories it is stored under, so `/Users/alice/...` and
    /// `/Users/zoe/...` do not sort the same way against a third path. That decides real behaviour, because
    /// when two artifacts answer to one framework name the search path listed first is the one the build
    /// resolves.
    ///
    /// A path under Tuist's cache directory is ordered on its path within that directory, which is the
    /// content hash and the artifact name, and so is identical everywhere the same graph is generated. That
    /// covers the collision the cache itself creates, a cached artifact against a vendored one. Everything
    /// else keeps its position relative to the source root, which is already stable for paths that do not
    /// escape the repository, and cached paths sort ahead of it, which is where they land today anyway by
    /// virtue of leading with `..`.
    ///
    /// What remains is two artifacts both stored at machine-specific locations outside the cache. Those have
    /// no machine-independent identity to order them by, which is what the ambiguity warning is for.
    private func searchPathOrder(
        for path: LinkGeneratorPath,
        sourceRootPath: AbsolutePath,
        cacheDirectory: AbsolutePath
    ) -> SearchPathOrder {
        let value = path.xcodeValue(sourceRootPath: sourceRootPath)
        guard case let .absolutePath(absolutePath) = path, absolutePath.isDescendant(of: cacheDirectory) else {
            return SearchPathOrder(rank: 1, identity: value, value: value)
        }
        return SearchPathOrder(rank: 0, identity: absolutePath.relative(to: cacheDirectory).pathString, value: value)
    }

    private func swiftSearchPathValues(
        precompiledArtifacts: Set<PrecompiledArtifact>,
        swiftFrameworkSearchPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        cacheDirectory: AbsolutePath
    ) -> (values: [String], linkPaths: Set<AbsolutePath>, symbolicLinks: [SideEffectDescriptor]) {
        let frameworkArtifacts = precompiledArtifacts.filter(\.canBeLinkedIntoSwiftSearchPath)
        let frameworkArtifactsByBasename = Dictionary(grouping: frameworkArtifacts, by: \.path.basename)

        let linkableArtifacts = frameworkArtifactsByBasename.values
            .filter { $0.count == 1 }
            .compactMap(\.first)
            .sorted { $0.path.pathString < $1.path.pathString }
        let conflictingFrameworkSearchPaths = frameworkArtifactsByBasename.values
            .filter { $0.count > 1 }
            .flatMap { $0.map(\.searchPath) }
        // `.xcframework` and other non-`.framework` artifacts are kept inline because they can't be
        // safely represented as a symbolic link (see `canBeLinkedIntoSwiftSearchPath`).
        let inlineSearchPaths = precompiledArtifacts
            .filter { !$0.canBeLinkedIntoSwiftSearchPath }
            .map(\.searchPath)

        var values: [String] = []
        var linkPaths: Set<AbsolutePath> = []
        var symbolicLinks: [SideEffectDescriptor] = []
        // The caller registers this target's cleanup directory unconditionally, so stale symbolic links (for
        // example `.xcframework` links created by older Tuist versions) are removed even when this target now
        // has no active `.framework` links to link into the consolidated Swift search directory.
        if !linkableArtifacts.isEmpty {
            values.append(LinkGeneratorPath.absolutePath(swiftFrameworkSearchPath).xcodeValue(sourceRootPath: sourceRootPath))
            linkPaths = Set(linkableArtifacts.map { artifact in
                swiftFrameworkSearchPath.appending(component: artifact.path.basename)
            })
            symbolicLinks = linkableArtifacts.map { artifact in
                .symbolicLink(
                    SymbolicLinkDescriptor(
                        path: swiftFrameworkSearchPath.appending(component: artifact.path.basename),
                        destination: artifact.path
                    )
                )
            }
        }

        values.append(
            contentsOf: xcodeValues(
                of: Set(conflictingFrameworkSearchPaths + inlineSearchPaths),
                sourceRootPath: sourceRootPath,
                cacheDirectory: cacheDirectory
            )
        )

        return (values: values, linkPaths: linkPaths, symbolicLinks: symbolicLinks)
    }

    /// Applies the settings to the target's base settings and to any configuration that already
    /// overrides one of the affected keys. Configuration-level keys shadow the base value entirely,
    /// so patching only the base would drop the flags for targets that override e.g.
    /// `OTHER_SWIFT_FLAGS` per configuration (mirrors `ModuleMapMapper`).
    private func apply(
        _ additions: [(key: String, values: [String])],
        to settings: Settings?,
        defaultSettings: DefaultSettings
    ) -> Settings {
        let settings = settings ?? Settings(base: [:], configurations: [:], defaultSettings: defaultSettings)
        return Settings(
            base: applied(additions, to: settings.base),
            baseDebug: settings.baseDebug,
            configurations: settings.configurations.mapValues { configuration in
                guard let configuration else { return nil }
                return configuration.with(settings: applied(additions, to: configuration.settings, onlyExistingKeys: true))
            },
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration
        )
    }

    private func applied(
        _ additions: [(key: String, values: [String])],
        to settings: SettingsDictionary,
        onlyExistingKeys: Bool = false
    ) -> SettingsDictionary {
        var settings = settings
        for (key, values) in additions where !values.isEmpty {
            if onlyExistingKeys, settings[key] == nil { continue }
            settings[key] = extended(settings[key], with: values)
        }
        return settings
    }

    private func extended(_ value: SettingsDictionary.Value?, with values: [String]) -> SettingsDictionary.Value {
        var current: [String]
        switch value ?? .array(["$(inherited)"]) {
        case let .array(existing):
            current = existing
        case let .string(string):
            current = string.split(separator: " ").map(String.init)
        }
        current.append(contentsOf: values)
        return .array(current)
    }
}
