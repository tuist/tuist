import Foundation
import Logging
import Path
import TuistCore
import XcodeGraph

/// Keeps cached macros out of Xcode's compilation-cache keys as absolute paths.
///
/// Swift keys a compilation on a macro plugin's path, never on its contents, and a cached macro lives under the
/// machine's cache directory. Each cached macro's directory is mapped to `/^macro-<binary cache hash>`, so the key is
/// the same on every machine and changes exactly when the macro's hash does. Every project gets the same mappings:
/// swift-build pushes `SWIFT_OTHER_PREFIX_MAPPINGS` from dependents onto package targets and warns when they differ.
///
/// Xcode 27 forwards `SWIFT_LOAD_BINARY_MACROS` through `-Xfrontend`, which the scanner never remaps, so targets that
/// load a cached macro load it through the `-load-plugin-executable` driver flag instead. The flag goes in
/// `SWIFT_TOOLCHAIN_FLAGS`, which Xcode passes to the driver ahead of `OTHER_SWIFT_FLAGS`, so overriding
/// `OTHER_SWIFT_FLAGS` (in a configuration or on the command line) cannot drop it. `ConfigGenerator` keeps
/// `SWIFT_LOAD_BINARY_MACROS` for every other macro, and for configurations whose toolchain flags shadow these.
public struct CachedMacroPrefixMappingGraphMapper: GraphMapping {
    private let compilationCachingEnabled: Bool

    public init(compilationCachingEnabled: Bool) {
        self.compilationCachingEnabled = compilationCachingEnabled
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) { // swiftlint:disable:this large_tuple
        let hashes = environment.cachedMacroHashes
        guard compilationCachingEnabled, !hashes.isEmpty,
              await XcodeCacheSettingsProjectMapper.isPrefixMappingSupported()
        else { return (graph, [], environment) }

        Logger.current.debug("Prefix-mapping \(hashes.count) cached macros to their binary cache hashes")

        let mappings = hashes
            .map { SettingValue.quoted("\($0.key.parentDirectory.pathString)=/^macro-\($0.value)") }
            .sorted()
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph
        graph.projects = graph.projects.mapValues { project in
            var project = project
            var base = project.settings.base
            base["SWIFT_OTHER_PREFIX_MAPPINGS"] = XcodeCachePrefixMappingWorkspaceMapper.appending(
                mappings,
                to: base["SWIFT_OTHER_PREFIX_MAPPINGS"]
            )
            project.settings = project.settings.with(base: base)
            project.targets = project.targets.mapValues { target in
                let flags = graphTraverser.allPrecompiledSwiftMacroExecutables(path: project.path, name: target.name)
                    .filter { executable in
                        guard let separator = executable.lastIndex(of: "#"),
                              let path = try? AbsolutePath(validating: String(executable[..<separator]))
                        else { return false }
                        return hashes[path] != nil
                    }
                    .sorted()
                    .flatMap { ["-load-plugin-executable", SettingValue.quoted($0)] }
                guard !flags.isEmpty else { return target }
                var target = target
                let settings = target.settings
                    ?? Settings(base: [:], configurations: [:], defaultSettings: project.settings.defaultSettings)
                var targetBase = settings.base
                targetBase["SWIFT_TOOLCHAIN_FLAGS"] = XcodeCachePrefixMappingWorkspaceMapper.appending(
                    flags,
                    to: targetBase["SWIFT_TOOLCHAIN_FLAGS"]
                )
                target.settings = settings.with(base: targetBase)
                return target
            }
            return project
        }
        return (graph, [], environment)
    }
}
