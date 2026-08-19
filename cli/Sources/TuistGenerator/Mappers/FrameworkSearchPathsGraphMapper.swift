import Foundation
import Path
import TuistAlert
import TuistConstants
import TuistCore
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
        let ambiguousFrameworkNames: [AmbiguousFrameworkName]
        var responseFile: FileDescriptor?
        /// Non-nil for targets that went through consolidation, including when the set is empty: the cleanup
        /// directory has to be registered either way so links left by earlier Tuist versions are still removed.
        var frameworkLinkPaths: Set<AbsolutePath>?
        var symbolicLinks: [SideEffectDescriptor] = []
    }

    private struct PrecompiledArtifact: Hashable {
        let path: AbsolutePath

        /// The names the artifact answers to on a framework search path. For an `.xcframework` these come from
        /// the `LibraryPath` of each framework slice in its `Info.plist`, not from the container's own name:
        /// the container can be named anything, and what a target imports is the framework inside it.
        /// Artifacts that contribute no `.framework` (a library slice, a `.a`) resolve through other flags and
        /// contribute no name here.
        let frameworkNames: Set<String>

        init(path: AbsolutePath, xcframeworkFrameworkNames: [AbsolutePath: Set<String>]) {
            self.path = path
            // Only an `.xcframework` needs the index: every other artifact is the bundle it is named after.
            frameworkNames = xcframeworkFrameworkNames[path]
                ?? (path.extension == "framework" ? [path.basenameWithoutExt] : [])
        }

        /// An artifact is the file it points at, so two references to one path stay a single artifact.
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.path == rhs.path }

        func hash(into hasher: inout Hasher) { hasher.combine(path) }

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

    /// Several precompiled artifacts that answer to one framework name on a target's search paths.
    private struct AmbiguousFrameworkName: Hashable {
        let name: String
        let paths: [AbsolutePath]
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

        let xcframeworkFrameworkNames = xcframeworkFrameworkNames(in: graph)

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
                    xcframeworkFrameworkNames: xcframeworkFrameworkNames
                )
            }
            .compactMap { $0 }

        var settingsByTarget: [TargetID: [(key: String, values: [String])]] = [:]
        var generatedFileSideEffects: [SideEffectDescriptor] = []
        var generatedSymbolicLinkSideEffects: [SideEffectDescriptor] = []
        var activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var activeFrameworkLinksByDirectory: [AbsolutePath: Set<AbsolutePath>] = [:]
        var ambiguousFrameworkNames: [AmbiguousFrameworkName] = []
        var targetsByAmbiguousFrameworkName: [AmbiguousFrameworkName: [String]] = [:]

        for output in outputs {
            settingsByTarget[output.id] = output.additions
            for ambiguousFrameworkName in output.ambiguousFrameworkNames {
                if targetsByAmbiguousFrameworkName[ambiguousFrameworkName] == nil {
                    ambiguousFrameworkNames.append(ambiguousFrameworkName)
                }
                targetsByAmbiguousFrameworkName[ambiguousFrameworkName, default: []].append(output.id.targetName)
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

        warnAboutAmbiguousFrameworkNames(ambiguousFrameworkNames, targets: targetsByAmbiguousFrameworkName)

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
        xcframeworkFrameworkNames: [AbsolutePath: Set<String>]
    ) throws -> TargetOutput? {
        // `precompiledSearchPathDependencies` rather than `searchablePathDependencies`: the latter builds a
        // `GraphDependencyReference` for every dependency reachable from the target, and everything below
        // reduces those to artifact paths and SDK search paths. On a binary-cache-substituted graph that is
        // hundreds of references per target materialized to be discarded. The two are held in agreement by
        // `PrecompiledSearchPathsDifferentialTests`.
        let searchPathDependencies = graphTraverser
            .precompiledSearchPathDependencies(path: input.id.projectPath, name: input.id.targetName)

        let precompiledArtifacts = Set(
            searchPathDependencies.precompiledPaths.map {
                PrecompiledArtifact(path: $0, xcframeworkFrameworkNames: xcframeworkFrameworkNames)
            }
        )
        let precompiledPaths = Set(precompiledArtifacts.map(\.searchPath))
        let sdkPaths = Set(searchPathDependencies.sdkSearchPaths.map { LinkGeneratorPath.string($0) })

        guard !precompiledPaths.isEmpty || !sdkPaths.isEmpty else { return nil }

        var artifactsByFrameworkName: [String: [AbsolutePath]] = [:]
        for artifact in precompiledArtifacts {
            for frameworkName in artifact.frameworkNames {
                artifactsByFrameworkName[frameworkName, default: []].append(artifact.path)
            }
        }
        let ambiguousFrameworkNames = artifactsByFrameworkName
            .filter { $0.value.count > 1 }
            .map { AmbiguousFrameworkName(name: $0.key, paths: $0.value.sorted()) }
            .sorted { $0.name < $1.name }

        var additions: [(key: String, values: [String])] = []
        guard precompiledPaths.count >= Self.consolidationThreshold else {
            additions.append((
                Self.frameworkSearchPathsSetting,
                xcodeValues(of: precompiledPaths.union(sdkPaths), sourceRootPath: input.sourceRootPath)
            ))
            return TargetOutput(
                id: input.id,
                responseFileDirectory: input.responseFileDirectory,
                additions: additions,
                ambiguousFrameworkNames: ambiguousFrameworkNames
            )
        }

        let responseFilePath = input.responseFileDirectory.appending(component: "\(input.id.targetName).resp")
        let precompiledXcodeValues = precompiledPaths
            .map { $0.xcodeValue(sourceRootPath: input.sourceRootPath) }
            .uniqued()
            .sorted()
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
            sourceRootPath: input.sourceRootPath
        )
        // FRAMEWORK_SEARCH_PATHS keeps only platform framework paths; Clang and the linker read the
        // precompiled paths from the response file via @file to keep command lines short.
        additions.append((
            Self.frameworkSearchPathsSetting,
            xcodeValues(of: sdkPaths, sourceRootPath: input.sourceRootPath)
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
            ambiguousFrameworkNames: ambiguousFrameworkNames,
            responseFile: FileDescriptor(path: responseFilePath, contents: Data(responseFileContents.utf8)),
            frameworkLinkPaths: swiftSearchPaths.linkPaths,
            symbolicLinks: swiftSearchPaths.symbolicLinks
        )
    }

    /// The framework names each `.xcframework` in the graph answers to, keyed by the container's path.
    ///
    /// The search path inputs carry artifact paths, and an `.xcframework` container can be named anything: what
    /// a target imports is the framework its slices carry. Reading that from the graph's dependencies once,
    /// rather than per target, keeps this off the per-target path that `precompiledSearchPathDependencies` was
    /// introduced to make cheap.
    private func xcframeworkFrameworkNames(in graph: Graph) -> [AbsolutePath: Set<String>] {
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
        return namesByPath
    }

    /// Reports framework bundles that share a name on one target rather than letting the framework search
    /// path order pick between them silently. That order comes from the artifacts' paths, and an artifact
    /// vendored outside the repository has no machine-independent identity to order it by, so the same
    /// graph can otherwise build against a different artifact on another machine.
    private func warnAboutAmbiguousFrameworkNames(
        _ ambiguousFrameworkNames: [AmbiguousFrameworkName],
        targets targetsByAmbiguousFrameworkName: [AmbiguousFrameworkName: [String]]
    ) {
        for ambiguousFrameworkName in ambiguousFrameworkNames {
            guard let targetNames = targetsByAmbiguousFrameworkName[ambiguousFrameworkName],
                  let firstTargetName = targetNames.first else { continue }
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
            let paths = ambiguousFrameworkName.paths.map(\.pathString).joined(separator: ", ")
            AlertController.current.warning(.alert(
                "\(scope) \(verb) on \(ambiguousFrameworkName.paths.count) precompiled artifacts providing '\(ambiguousFrameworkName.name)': \(paths). Only one of them is resolved through the framework search paths, and which one wins follows where the artifacts are stored, so another machine can resolve a different one.",
                takeaway: "Depend on a single artifact providing '\(ambiguousFrameworkName.name)' so what a target builds against doesn't depend on where the artifacts are stored."
            ))
        }
    }

    private func xcodeValues(of paths: Set<LinkGeneratorPath>, sourceRootPath: AbsolutePath) -> [String] {
        paths.map { $0.xcodeValue(sourceRootPath: sourceRootPath) }.uniqued().sorted()
    }

    private func swiftSearchPathValues(
        precompiledArtifacts: Set<PrecompiledArtifact>,
        swiftFrameworkSearchPath: AbsolutePath,
        sourceRootPath: AbsolutePath
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
                sourceRootPath: sourceRootPath
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
