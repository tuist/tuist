import Foundation
import Path
import TuistConstants
import TuistCore
import XcodeGraph

/// Configures Xcode schemes so the [Low-Level Debugger (LLDB)](https://lldb.llvm.org/) can load
/// Swift modules that were replaced with artifacts from Tuist's module cache.
///
/// The generated pre-action follows the approach used by rules_xcodeproj: it refreshes a
/// project-local debugger initialization file using the selected target's resolved build settings.
public struct CachedModulesDebuggingGraphMapper: GraphMapping {
    private static let updateActionTitle = "Update Tuist cache debugger settings"

    public init() {}

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        guard let graphWithSources = environment.initialGraphWithSources else {
            return (graph, [], environment)
        }

        let cachedArtifactPaths = precompiledPaths(in: graph).subtracting(precompiledPaths(in: graphWithSources))
        guard !cachedArtifactPaths.isEmpty else {
            return (graph, [], environment)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        var sideEffects: [SideEffectDescriptor] = []

        let projects = try Dictionary(uniqueKeysWithValues: graph.projects.map { path, project in
            var project = project
            project.schemes = try mappedSchemes(
                project.schemes,
                scope: "project-\(project.name)",
                graph: graph,
                graphTraverser: graphTraverser,
                cachedArtifactPaths: cachedArtifactPaths,
                sideEffects: &sideEffects
            )
            return (path, project)
        })

        var workspace = graph.workspace
        workspace.schemes = try mappedSchemes(
            workspace.schemes,
            scope: "workspace-\(workspace.name)",
            graph: graph,
            graphTraverser: graphTraverser,
            cachedArtifactPaths: cachedArtifactPaths,
            sideEffects: &sideEffects
        )
        var mappedGraph = graph
        mappedGraph.projects = projects
        mappedGraph.workspace = workspace

        return (mappedGraph, sideEffects, environment)
    }

    private func mappedSchemes(
        _ schemes: [Scheme],
        scope: String,
        graph: Graph,
        graphTraverser: GraphTraversing,
        cachedArtifactPaths: Set<AbsolutePath>,
        sideEffects: inout [SideEffectDescriptor]
    ) throws -> [Scheme] {
        try schemes.map { scheme in
            var scheme = scheme

            if let runAction = scheme.runAction,
               runAction.attachDebugger,
               let target = try runTarget(
                   for: scheme,
                   graphTraverser: graphTraverser,
                   cachedArtifactPaths: cachedArtifactPaths
               )
            {
                let artifacts = try cachedArtifacts(
                    reachableFrom: target,
                    graphTraverser: graphTraverser,
                    cachedArtifactPaths: cachedArtifactPaths
                )
                let configuration = try debuggerConfiguration(
                    scope: scope,
                    schemeName: scheme.name,
                    actionName: "run",
                    target: target,
                    originalLLDBInitFile: runAction.customLLDBInitFile,
                    artifacts: artifacts,
                    graph: graph
                )
                scheme.runAction = runAction.with(
                    customLLDBInitFile: configuration.lldbInitPath,
                    preActions: prepending(configuration.preAction, to: runAction.preActions)
                )
                sideEffects.append(.file(configuration.initialLLDBInitFile))
            }

            if var testAction = scheme.testAction, testAction.attachDebugger {
                let testTargets = testAction.targets.map(\.target) + (testAction.testPlans ?? []).flatMap {
                    $0.testTargets.map(\.target)
                }
                let artifacts = try testTargets.reduce(into: Set<AbsolutePath>()) { artifacts, target in
                    artifacts.formUnion(try cachedArtifacts(
                        reachableFrom: target,
                        graphTraverser: graphTraverser,
                        cachedArtifactPaths: cachedArtifactPaths
                    ))
                }
                if let target = testAction.expandVariableFromTarget ?? testTargets.first,
                   !artifacts.isEmpty
                {
                    let configuration = try debuggerConfiguration(
                        scope: scope,
                        schemeName: scheme.name,
                        actionName: "test",
                        target: target,
                        originalLLDBInitFile: testAction.customLLDBInitFile,
                        artifacts: artifacts,
                        graph: graph
                    )
                    testAction.customLLDBInitFile = configuration.lldbInitPath
                    testAction.preActions = prepending(configuration.preAction, to: testAction.preActions)
                    scheme.testAction = testAction
                    sideEffects.append(.file(configuration.initialLLDBInitFile))
                }
            }

            return scheme
        }
    }

    private func runTarget(
        for scheme: Scheme,
        graphTraverser: GraphTraversing,
        cachedArtifactPaths: Set<AbsolutePath>
    ) throws -> TargetReference? {
        guard let target = scheme.runAction?.executable ?? scheme.buildAction?.targets.first else {
            return nil
        }
        let artifacts = try cachedArtifacts(
            reachableFrom: target,
            graphTraverser: graphTraverser,
            cachedArtifactPaths: cachedArtifactPaths
        )
        return artifacts.isEmpty ? nil : target
    }

    private func cachedArtifacts(
        reachableFrom target: TargetReference,
        graphTraverser: GraphTraversing,
        cachedArtifactPaths: Set<AbsolutePath>
    ) throws -> Set<AbsolutePath> {
        try Set(
            graphTraverser
                .searchablePathDependencies(path: target.projectPath, name: target.name)
                .compactMap(\.precompiledPath)
                .filter(cachedArtifactPaths.contains)
        )
    }

    private func debuggerConfiguration(
        scope: String,
        schemeName: String,
        actionName: String,
        target: TargetReference,
        originalLLDBInitFile: AbsolutePath?,
        artifacts: Set<AbsolutePath>,
        graph: Graph
    ) throws -> DebuggerConfiguration {
        guard let project = graph.projects[target.projectPath] else {
            throw CachedModulesDebuggingGraphMapperError.missingProject(target.projectPath)
        }

        let fileName = safeFileName("\(scope)-\(schemeName)-\(actionName)")
        let directory = project.sourceRootPath.appending(
            components: Constants.DerivedDirectory.name,
            "TuistCacheDebugging"
        )
        let lldbInitPath = directory.appending(component: "\(fileName).lldbinit")
        let overlayPath = directory.appending(component: "\(fileName)-prefix-remap.yaml")
        let searchPaths = Set(artifacts.map(\.parentDirectory)).sorted()
        let initialContents = lldbInitContents(
            originalLLDBInitFile: originalLLDBInitFile,
            frameworkSearchPaths: searchPaths,
            moduleSearchPaths: searchPaths
        )
        let preAction = ExecutionAction(
            title: Self.updateActionTitle,
            scriptText: debuggerUpdateScript(
                lldbInitPath: lldbInitPath,
                overlayPath: overlayPath,
                originalLLDBInitFile: originalLLDBInitFile,
                searchPaths: searchPaths
            ),
            target: target,
            shellPath: "/bin/sh",
            showEnvVarsInLog: false
        )
        return DebuggerConfiguration(
            lldbInitPath: lldbInitPath,
            initialLLDBInitFile: FileDescriptor(
                path: lldbInitPath,
                contents: Data(initialContents.utf8)
            ),
            preAction: preAction
        )
    }

    private func prepending(_ action: ExecutionAction, to actions: [ExecutionAction]) -> [ExecutionAction] {
        [action] + actions.filter { $0.title != Self.updateActionTitle }
    }

    private func precompiledPaths(in graph: Graph) -> Set<AbsolutePath> {
        Set(
            (Array(graph.dependencies.keys) + graph.dependencies.values.flatMap(Array.init))
                .compactMap(precompiledPath)
        )
    }

    private func precompiledPath(of dependency: GraphDependency) -> AbsolutePath? {
        switch dependency {
        case let .foreignBuildOutput(output): output.path
        case let .xcframework(xcframework): xcframework.path
        case let .framework(path, _, _, _, _, _, _): path
        case let .library(path, _, _, _, _): path
        case .bundle, .macro, .packageProduct, .sdk, .target: nil
        }
    }

    private func lldbInitContents(
        originalLLDBInitFile: AbsolutePath?,
        frameworkSearchPaths: [AbsolutePath],
        moduleSearchPaths: [AbsolutePath]
    ) -> String {
        var lines: [String] = []
        if let originalLLDBInitFile {
            lines.append("command source -s 0 \(lldbQuoted(originalLLDBInitFile.pathString))")
        }
        lines.append(lldbSetting("target.swift-framework-search-paths", values: frameworkSearchPaths.map(\.pathString)))
        lines.append(lldbSetting("target.swift-module-search-paths", values: moduleSearchPaths.map(\.pathString)))
        lines.append("settings set symbols.use-swift-explicit-module-loader false")
        return lines.joined(separator: "\n") + "\n"
    }

    private func lldbSetting(_ setting: String, values: [String]) -> String {
        "settings set \(setting) " + values.map(lldbQuoted).joined(separator: " ")
    }

    private func lldbQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func safeFileName(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                String(UnicodeScalar(byte))
            default:
                String(format: "_%02X", byte)
            }
        }.joined()
    }

    private func debuggerUpdateScript(
        lldbInitPath: AbsolutePath,
        overlayPath: AbsolutePath,
        originalLLDBInitFile: AbsolutePath?,
        searchPaths: [AbsolutePath]
    ) -> String {
        let initialSearchPathArguments = searchPaths.map { shellQuoted($0.pathString) }.joined(separator: " ")
        let sourceOriginal = originalLLDBInitFile.map {
            "lldb_setting command-source \(shellQuoted($0.pathString))"
        } ?? ""

        return """
        set -eu

        lldb_init_file=\(shellQuoted(lldbInitPath.pathString))
        overlay_file=\(shellQuoted(overlayPath.pathString))
        mkdir -p "$(dirname "$lldb_init_file")"

        lldb_escape() {
          printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
        }

        lldb_setting() {
          setting="$1"
          shift
          if [ "$setting" = "command-source" ]; then
            printf 'command source -s 0 "%s"\\n' "$(lldb_escape "$1")"
            return
          fi
          printf 'settings set %s' "$setting"
          for value in "$@"; do
            printf ' "%s"' "$(lldb_escape "$value")"
          done
          printf '\\n'
        }

        json_escape() {
          printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
        }

        {
          \(sourceOriginal)
          set -- \(initialSearchPathArguments)
          for path in "${TARGET_BUILD_DIR:-}" "${BUILT_PRODUCTS_DIR:-}" "${CONFIGURATION_BUILD_DIR:-}"; do
            if [ -n "$path" ]; then
              set -- "$@" "$path"
            fi
          done
          lldb_setting target.swift-framework-search-paths "$@"
          lldb_setting target.swift-module-search-paths "$@"
          printf 'settings set symbols.use-swift-explicit-module-loader false\n'

          if [ "${COMPILATION_CACHE_ENABLE_CACHING:-NO}" = "YES" ]; then
            derived_data_dir="${BUILD_DIR%%/Build/*}"
            cache_kind=builtin
            if [ "${COMPILATION_CACHE_ENABLE_PLUGIN:-NO}" = "YES" ]; then
              cache_kind=plugin
            fi
            cas_path="$derived_data_dir/CompilationCache.noindex/$cache_kind"
            plugin_path="${COMPILATION_CACHE_PLUGIN_PATH:-${DEVELOPER_DIR:-}/usr/lib/libToolchainCASPlugin.dylib}"
            lldb_setting symbols.cas-path "$cas_path"
            lldb_setting symbols.cas-plugin-path "$plugin_path"

            set --
            if [ -n "${COMPILATION_CACHE_REMOTE_SERVICE_PATH:-}" ]; then
              set -- "$@" "remote-service-path=$COMPILATION_CACHE_REMOTE_SERVICE_PATH"
            fi
            expects_plugin_option=NO
            for flag in ${OTHER_SWIFT_FLAGS:-}; do
              if [ "$expects_plugin_option" = "YES" ]; then
                set -- "$@" "$flag"
                expects_plugin_option=NO
              elif [ "$flag" = "-cas-plugin-option" ]; then
                expects_plugin_option=YES
              fi
            done
            if [ "$#" -gt 0 ]; then
              lldb_setting symbols.cas-plugin-options "$@"
            fi

            sdk_path="${SDKROOT:-}"
            developer_path="${DEVELOPER_DIR:-}"
            toolchain_path="$developer_path/Toolchains/XcodeDefault.xctoolchain"
            printf '{"version":0,"case-sensitive":"false","redirecting-with":"fallthrough","roots":[' > "$overlay_file"
            printf '{"type":"directory-remap","name":"/^sdk","external-contents":"%s"},' "$(json_escape "$sdk_path")" >> "$overlay_file"
            printf '{"type":"directory-remap","name":"/^toolchain","external-contents":"%s"},' "$(json_escape "$toolchain_path")" >> "$overlay_file"
            printf '{"type":"directory-remap","name":"/^xcode","external-contents":"%s"}]}' "$(json_escape "$developer_path")" >> "$overlay_file"
            printf 'settings set target.swift-extra-clang-flags -- -ivfsoverlay "%s"\\n' "$(lldb_escape "$overlay_file")"
          fi
        } > "$lldb_init_file"
        """
    }
}

private struct DebuggerConfiguration {
    let lldbInitPath: AbsolutePath
    let initialLLDBInitFile: FileDescriptor
    let preAction: ExecutionAction
}

private enum CachedModulesDebuggingGraphMapperError: Error {
    case missingProject(AbsolutePath)
}

extension RunAction {
    fileprivate func with(customLLDBInitFile: AbsolutePath, preActions: [ExecutionAction]) -> RunAction {
        RunAction(
            configurationName: configurationName,
            attachDebugger: attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            filePath: filePath,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions,
            metalOptions: metalOptions,
            expandVariableFromTarget: expandVariableFromTarget,
            askForAppToLaunch: askForAppToLaunch,
            launchStyle: launchStyle,
            appClipInvocationURL: appClipInvocationURL,
            customWorkingDirectory: customWorkingDirectory,
            useCustomWorkingDirectory: useCustomWorkingDirectory
        )
    }
}
