import Foundation
import Path
import TuistConstants
import TuistCore
import XcodeGraph

/// Configures Xcode schemes so the [Low-Level Debugger (LLDB)](https://lldb.llvm.org/) can load
/// Swift modules that were replaced with artifacts from Tuist's module cache and
/// resolve source paths normalized by Xcode's compilation cache.
///
/// The generated pre-action follows the approach used by rules_xcodeproj: it refreshes a
/// project-local debugger initialization file using the selected target's resolved build settings.
public struct CachedModulesDebuggingGraphMapper: GraphMapping {
    private static let updateActionTitle = "Update Tuist cache debugger settings"

    private let compilationCachingEnabled: Bool

    public init(compilationCachingEnabled: Bool = false) {
        self.compilationCachingEnabled = compilationCachingEnabled
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let cachedArtifactPaths = environment.initialGraphWithSources.map {
            precompiledPaths(in: graph).subtracting(precompiledPaths(in: $0))
        } ?? []
        guard compilationCachingEnabled || !cachedArtifactPaths.isEmpty else {
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

            if let runAction = scheme.runAction ?? defaultRunAction(for: scheme, graphTraverser: graphTraverser),
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
                if let configuration = try debuggerConfiguration(
                    scope: scope,
                    schemeName: scheme.name,
                    actionName: "run",
                    target: target,
                    originalLLDBInitFile: runAction.customLLDBInitFile,
                    preActions: runAction.preActions,
                    artifacts: artifacts,
                    graph: graph
                ) {
                    scheme.runAction = runAction.with(
                        customLLDBInitFile: configuration.lldbInitPath,
                        preActions: prepending(configuration.preAction, to: runAction.preActions)
                    )
                    sideEffects.append(.file(configuration.initialLLDBInitFile))
                }
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
                   compilationCachingEnabled || !artifacts.isEmpty
                {
                    if let configuration = try debuggerConfiguration(
                        scope: scope,
                        schemeName: scheme.name,
                        actionName: "test",
                        target: target,
                        originalLLDBInitFile: testAction.customLLDBInitFile,
                        preActions: testAction.preActions,
                        artifacts: artifacts,
                        graph: graph
                    ) {
                        testAction.customLLDBInitFile = configuration.lldbInitPath
                        testAction.preActions = prepending(configuration.preAction, to: testAction.preActions)
                        scheme.testAction = testAction
                        sideEffects.append(.file(configuration.initialLLDBInitFile))
                    }
                }
            }

            return scheme
        }
    }

    private func defaultRunAction(for scheme: Scheme, graphTraverser: GraphTraversing) -> RunAction? {
        guard let target = graphTraverser.schemeRunnableTarget(scheme: scheme) else { return nil }
        switch target.target.product {
        case .appExtension, .messagesExtension, .extensionKitExtension:
            return nil
        default:
            break
        }

        // Match SchemeDescriptorsGenerator's implicit launch action, including its enabled checkers.
        return RunAction(
            configurationName: target.project.defaultDebugBuildConfigurationName,
            attachDebugger: true,
            customLLDBInitFile: nil,
            executable: nil,
            filePath: nil,
            arguments: nil,
            diagnosticsOptions: SchemeDiagnosticsOptions(
                mainThreadCheckerEnabled: true,
                performanceAntipatternCheckerEnabled: true
            )
        )
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
        return compilationCachingEnabled || !artifacts.isEmpty ? target : nil
    }

    private func cachedArtifacts(
        reachableFrom target: TargetReference,
        graphTraverser: GraphTraversing,
        cachedArtifactPaths: Set<AbsolutePath>
    ) throws -> Set<AbsolutePath> {
        guard !cachedArtifactPaths.isEmpty else { return [] }
        return try Set(
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
        preActions: [ExecutionAction],
        artifacts: Set<AbsolutePath>,
        graph: Graph
    ) throws -> DebuggerConfiguration? {
        guard let project = graph.projects[target.projectPath] else {
            throw CachedModulesDebuggingGraphMapperError.missingProject(target.projectPath)
        }

        let renderer = CacheDebuggerSettingsRenderer()
        let fileName = renderer.safeFileName("\(scope)-\(schemeName)-\(actionName)")
        let directory = project.sourceRootPath.appending(
            components: Constants.DerivedDirectory.name,
            "TuistCacheDebugging"
        )
        let lldbInitPath = directory.appending(component: "\(fileName).lldbinit")
        if originalLLDBInitFile == lldbInitPath,
           preActions.contains(where: { $0.title == Self.updateActionTitle })
        {
            return nil
        }
        let overlayPath = directory.appending(component: "\(fileName)-prefix-remap.yaml")
        let searchPaths = Set(artifacts.map(\.parentDirectory)).sorted()
        let initialContents = renderer.lldbInitContents(
            originalLLDBInitFile: originalLLDBInitFile,
            frameworkSearchPaths: searchPaths,
            moduleSearchPaths: searchPaths
        )
        let preAction = ExecutionAction(
            title: Self.updateActionTitle,
            scriptText: renderer.debuggerUpdateScript(
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
}

/// Renders debugger initialization files and the scripts that refresh their resolved build settings.
private struct CacheDebuggerSettingsRenderer {
    func lldbInitContents(
        originalLLDBInitFile: AbsolutePath?,
        frameworkSearchPaths: [AbsolutePath],
        moduleSearchPaths: [AbsolutePath]
    ) -> String {
        var lines: [String] = []
        if let originalLLDBInitFile {
            lines.append("command source -s 0 \(lldbQuoted(originalLLDBInitFile.pathString))")
        }
        if !frameworkSearchPaths.isEmpty || !moduleSearchPaths.isEmpty {
            lines.append(lldbSetting("target.swift-framework-search-paths", values: frameworkSearchPaths.map(\.pathString)))
            lines.append(lldbSetting("target.swift-module-search-paths", values: moduleSearchPaths.map(\.pathString)))
            lines.append("settings set symbols.use-swift-explicit-module-loader false")
        }
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

    func safeFileName(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                String(UnicodeScalar(byte))
            default:
                String(format: "_%02X", byte)
            }
        }.joined()
    }

    func debuggerUpdateScript(
        lldbInitPath: AbsolutePath,
        overlayPath: AbsolutePath,
        originalLLDBInitFile: AbsolutePath?,
        searchPaths: [AbsolutePath]
    ) -> String {
        let moduleSettings = searchPaths.isEmpty ? "" : cachedModulesUpdateScript(searchPaths: searchPaths)
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
          :
          \(sourceOriginal)
          \(moduleSettings)
        } > "$lldb_init_file"

        \(sourceMappingScript)
        """
    }

    private func cachedModulesUpdateScript(searchPaths: [AbsolutePath]) -> String {
        let initialSearchPathArguments = searchPaths.map { shellQuoted($0.pathString) }.joined(separator: " ")
        return """
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
          toolchain_path="${DT_TOOLCHAIN_DIR:-$developer_path/Toolchains/XcodeDefault.xctoolchain}"
          printf '{"version":0,"case-sensitive":"false","redirecting-with":"fallthrough","roots":[' > "$overlay_file"
          printf '{"type":"directory-remap","name":"/^sdk","external-contents":"%s"},' "$(json_escape "$sdk_path")" >> "$overlay_file"
          printf '{"type":"directory-remap","name":"/^toolchain","external-contents":"%s"},' "$(json_escape "$toolchain_path")" >> "$overlay_file"
          printf '{"type":"directory-remap","name":"/^xcode","external-contents":"%s"}]}' "$(json_escape "$developer_path")" >> "$overlay_file"
          printf 'settings set target.swift-extra-clang-flags -- -ivfsoverlay "%s"\\n' "$(lldb_escape "$overlay_file")"
        fi
        """
    }

    /// Reads the build system's resolved mapping lists without treating their contents as shell code.
    private var sourceMappingScript: String {
        #"""
        /usr/bin/python3 - "$lldb_init_file" <<'TUIST_SOURCE_MAP'
        import os
        import shlex
        import sys

        environment = os.environ
        if environment.get("COMPILATION_CACHE_ENABLE_CACHING") != "YES":
            sys.exit(0)

        mappings = []

        def append_mapping(prefix, path):
            mapping = (prefix, path)
            if prefix and path and mapping not in mappings:
                mappings.append(mapping)

        prefix_mapping_enabled = False
        for language in ("SWIFT", "CLANG"):
            if environment.get(language + "_ENABLE_PREFIX_MAPPING") != "YES":
                continue
            prefix_mapping_enabled = True
            for value in shlex.split(environment.get(language + "_OTHER_PREFIX_MAPPINGS", "")):
                path, separator, prefix = value.rpartition("=")
                if separator:
                    append_mapping(prefix, path)
            if environment.get(language + "_ENABLE_PROJECT_PREFIX_MAPPING") == "YES":
                for prefix, setting in (
                    ("/^src", "PROJECT_DIR"),
                    ("/^derived", "PROJECT_TEMP_DIR"),
                    ("/^built", "BUILT_PRODUCTS_DIR"),
                ):
                    append_mapping(prefix, environment.get(setting, ""))

        if prefix_mapping_enabled:
            developer_path = environment.get("DEVELOPER_DIR", "")
            toolchain_path = environment.get("DT_TOOLCHAIN_DIR", "")
            if not toolchain_path and developer_path:
                toolchain_path = developer_path + "/Toolchains/XcodeDefault.xctoolchain"
            append_mapping("/^sdk", environment.get("SDKROOT", ""))
            append_mapping("/^toolchain", toolchain_path)
            append_mapping("/^xcode", developer_path)

        def lldb_quoted(value):
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'

        if mappings:
            arguments = " ".join(lldb_quoted(value) for mapping in mappings for value in mapping)
            with open(sys.argv[1], "a", encoding="utf-8") as output:
                output.write("settings append target.source-map " + arguments + "\n")
        TUIST_SOURCE_MAP
        """#
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
