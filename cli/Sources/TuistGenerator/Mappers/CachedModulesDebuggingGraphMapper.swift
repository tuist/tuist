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
                sourceMappings: environment.cachedModuleSourceMappings,
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
            sourceMappings: environment.cachedModuleSourceMappings,
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
        sourceMappings: [AbsolutePath: [DebuggerSourceMapping]],
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
                    nativeTargets: [target],
                    originalLLDBInitFile: runAction.customLLDBInitFile,
                    preActions: runAction.preActions,
                    artifacts: artifacts,
                    sourceMappings: sourceMappings,
                    graph: graph
                ) {
                    scheme.runAction = runAction.with(
                        customLLDBInitFile: configuration.lldbInitPath,
                        preActions: prepending(configuration.preAction, to: runAction.preActions)
                    )
                    sideEffects.append(.file(configuration.initialLLDBInitFile))
                    if let sourceMappingsFile = configuration.sourceMappingsFile {
                        sideEffects.append(.file(sourceMappingsFile))
                    }
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
                        nativeTargets: testTargets,
                        originalLLDBInitFile: testAction.customLLDBInitFile,
                        preActions: testAction.preActions,
                        artifacts: artifacts,
                        sourceMappings: sourceMappings,
                        graph: graph
                    ) {
                        testAction.customLLDBInitFile = configuration.lldbInitPath
                        testAction.preActions = prepending(configuration.preAction, to: testAction.preActions)
                        scheme.testAction = testAction
                        sideEffects.append(.file(configuration.initialLLDBInitFile))
                        if let sourceMappingsFile = configuration.sourceMappingsFile {
                            sideEffects.append(.file(sourceMappingsFile))
                        }
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
        nativeTargets: [TargetReference],
        originalLLDBInitFile: AbsolutePath?,
        preActions: [ExecutionAction],
        artifacts: Set<AbsolutePath>,
        sourceMappings: [AbsolutePath: [DebuggerSourceMapping]],
        graph: Graph
    ) throws -> DebuggerConfiguration? {
        guard let project = graph.projects[target.projectPath] else {
            throw CachedModulesDebuggingGraphMapperError.missingProject(target.projectPath)
        }

        let renderer = CacheDebuggerSettingsRenderer()
        let fileName = renderer.safeFileName("\(scope)-\(schemeName)-\(actionName)")
        let directory = project.sourceRootPath.appending(
            components: Constants.DerivedDirectory.name,
            Constants.DerivedDirectory.tuistCacheDebugging
        )
        let lldbInitPath = directory.appending(component: "\(fileName).lldbinit")
        if originalLLDBInitFile == lldbInitPath,
           preActions.contains(where: { $0.title == Self.updateActionTitle })
        {
            return nil
        }
        let overlayPath = directory.appending(component: "\(fileName)-prefix-remap.yaml")
        let searchPaths = Set(artifacts.map(\.parentDirectory)).sorted()
        let mappings = Set(artifacts.flatMap { sourceMappings[$0, default: []] })
            .sorted { $0.original.pathString < $1.original.pathString }
        let sourceMappingsPath = directory.appending(component: "\(fileName)-sources.json")
        let requiresLinkedDebugInformation = (Array(graph.dependencies.keys) + graph.dependencies.values.flatMap(Array.init))
            .contains {
                if case let .xcframework(xcframework) = $0 {
                    return artifacts.contains(xcframework.path) && xcframework.linking == .static
                }
                return false
            }
        let destinations = Dictionary(grouping: mappings, by: \.original)
        guard destinations.values.allSatisfy({ Set($0.map(\.current)).count == 1 }) else {
            throw CachedModulesDebuggingGraphMapperError.ambiguousSourceMappings
        }
        let sourceMappingsFile = mappings.isEmpty ? nil : FileDescriptor(
            path: sourceMappingsPath,
            contents: try JSONEncoder().encode(DebuggerSourceMappingPlan(
                mappings: mappings.map { [$0.original.pathString, $0.current.pathString] },
                artifacts: artifacts.sorted().map(\.pathString),
                nativeProducts: nativeProducts(reachableFrom: nativeTargets, graph: graph).sorted(),
                requiresLinkedDebugInformation: requiresLinkedDebugInformation
            ))
        )
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
                searchPaths: searchPaths,
                sourceMappingsPath: sourceMappingsFile?.path
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
            preAction: preAction,
            sourceMappingsFile: sourceMappingsFile
        )
    }

    private func nativeProducts(reachableFrom roots: [TargetReference], graph: Graph) -> Set<String> {
        var pending = roots.map { GraphDependency.target(name: $0.name, path: $0.projectPath) }
        var visited = Set<GraphDependency>()
        var products = Set<String>()
        while let dependency = pending.popLast() {
            guard visited.insert(dependency).inserted else { continue }
            if case let .target(name, path, _) = dependency, let target = graph.projects[path]?.targets[name] {
                products.insert(target.productNameWithExtension)
            }
            pending.append(contentsOf: graph.dependencies[dependency, default: []])
        }
        return products
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
        if originalLLDBInitFile == nil {
            // Xcode skips its user initializer when a scheme supplies a custom one.
            // Check at debugger startup, not generation, since this file can be shared.
            lines.append(
                #"script import os; p = os.path.expanduser("~/.lldbinit-Xcode"); p = p if os.path.isfile(p) else os.path.expanduser("~/.lldbinit"); "# +
                    homeInitializerScript
            )
        }
        if let originalLLDBInitFile {
            lines.append("command source -s 0 \(lldbQuoted(originalLLDBInitFile.pathString))")
        }
        if !frameworkSearchPaths.isEmpty || !moduleSearchPaths.isEmpty {
            lines.append(lldbSetting("target.swift-framework-search-paths", values: frameworkSearchPaths.map(\.pathString)))
            lines.append(lldbSetting("target.swift-module-search-paths", values: moduleSearchPaths.map(\.pathString)))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private var homeInitializerScript: String {
        [
            "_tuist_init_options = lldb.SBCommandInterpreterRunOptions();",
            "_tuist_init_options.SetEchoCommands(False);",
            "_tuist_init_options.SetPrintResults(True);",
            "_tuist_init_options.SetPrintErrors(True);",
            "_tuist_init_options.SetStopOnError(False);",
            "_tuist_init_options.SetStopOnContinue(True);",
            "_tuist_init_options.SetAddToHistory(False);",
            "lldb.debugger.GetCommandInterpreter().HandleCommandsFromFile("
                + "lldb.SBFileSpec(p), lldb.SBExecutionContext(), _tuist_init_options, lldb.SBCommandReturnObject()) "
                + "if os.path.isfile(p) else None",
        ].joined(separator: " ")
    }

    private func lldbSetting(_ setting: String, values: [String]) -> String {
        "settings set \(setting) " + values.map(lldbQuoted).joined(separator: " ")
    }

    private func lldbQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
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
        searchPaths: [AbsolutePath],
        sourceMappingsPath: AbsolutePath?
    ) -> String {
        let moduleSettings = searchPaths.isEmpty ? "" : cachedModulesUpdateScript(searchPaths: searchPaths)
        let sourceOriginal = originalLLDBInitFile.map {
            "lldb_setting command-source \(shellQuoted($0.pathString))"
        } ?? ""
        let sourceHome = originalLLDBInitFile == nil ? """
        if [ -n "${HOME:-}" ]; then
          if [ -f "$HOME/.lldbinit-Xcode" ]; then
            lldb_setting command-source-home "$HOME/.lldbinit-Xcode"
          elif [ -f "$HOME/.lldbinit" ]; then
            lldb_setting command-source-home "$HOME/.lldbinit"
          fi
        fi
        """ : ""

        // Replace home-file and stale source maps, but let an explicit initializer extend or override the map.
        // Resolve it separately so an unreadable prefix map still leaves the user initializer sourced.
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
          if [ "$setting" = "command-source-home" ]; then
            printf 'script import os; p = "%s"; \(homeInitializerScript)\\n' "$(lldb_escape "$1")"
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

        source_map_file="$(mktemp "$lldb_init_file.XXXXXX")"
        trap 'rm -f "$source_map_file"' EXIT
        source_map_status=0
        \(sourceMappingScript(sourceMappingsPath: sourceMappingsPath))

        {
          \(sourceHome)
          cat "$source_map_file"
          \(sourceOriginal)
          \(compilationCacheUpdateScript)
          \(moduleSettings)
        } > "$lldb_init_file"
        exit "$source_map_status"
        """
    }

    /// Without the CAS, LLDB cannot load the modules that cached compilations reference by CAS ID, so it cannot
    /// reconstruct Swift types and expressions fail. Xcode does not configure it.
    ///
    /// Xcode does not export the default `COMPILATION_CACHE_CAS_PATH`, `$(DERIVED_DATA_DIR)/CompilationCache.noindex`,
    /// to scheme actions. `-derivedDataPath` builds keep the cache next to `Build`.
    private var compilationCacheUpdateScript: String {
        """
        if [ "${COMPILATION_CACHE_ENABLE_CACHING:-NO}" = "YES" ]; then
          cas_root="${COMPILATION_CACHE_CAS_PATH:-${DERIVED_DATA_DIR:-${BUILD_DIR%%/Build/*}}/CompilationCache.noindex}"
          if [ "${COMPILATION_CACHE_ENABLE_PLUGIN:-NO}" = "YES" ]; then
            lldb_setting symbols.cas-path "$cas_root/plugin"
            lldb_setting symbols.cas-plugin-path "${COMPILATION_CACHE_PLUGIN_PATH:-${DEVELOPER_DIR:-}/usr/lib/libToolchainCASPlugin.dylib}"

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
          else
            lldb_setting symbols.cas-path "$cas_root/builtin"
            lldb_setting symbols.cas-plugin-path ""
          fi
        fi
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

        if [ "${COMPILATION_CACHE_ENABLE_CACHING:-NO}" = "YES" ]; then
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

    /// Reads the build system's evaluated mappings without reparsing characters introduced by macro expansion.
    private func sourceMappingScript(sourceMappingsPath: AbsolutePath?) -> String {
        #"""
        /usr/bin/python3 - "$source_map_file" \#(shellQuoted(sourceMappingsPath?
                .pathString ?? "")) <<'TUIST_SOURCE_MAP' || source_map_status=$?
        import json
        import os
        import sys

        environment = os.environ
        mappings = {}
        plan = None
        if sys.argv[2]:
            with open(sys.argv[2], encoding="utf-8") as source_mappings:
                plan = json.load(source_mappings)

        target_temp_dir = environment.get("TARGET_TEMP_DIR", "")
        prefix_mapping_enabled = environment.get("COMPILATION_CACHE_ENABLE_CACHING") == "YES" and any(
            environment.get(language + "_ENABLE_PREFIX_MAPPING") == "YES" for language in ("SWIFT", "CLANG")
        )
        # Xcode expands path variables after parsing build-setting lists. Their exported string
        # representation can contain literal quotes or backslashes that are not shell syntax.
        if prefix_mapping_enabled and target_temp_dir:
            try:
                with open(os.path.join(target_temp_dir, "compilation-prefix-map.json"), encoding="utf-8") as prefix_map:
                    mappings.update(json.load(prefix_map))
            except FileNotFoundError:
                pass

        # Xcode's prefix-map file omits the compiler's implicit toolchain alias on some versions.
        if mappings and prefix_mapping_enabled:
            developer_path = environment.get("DEVELOPER_DIR", "")
            toolchain_path = environment.get("DT_TOOLCHAIN_DIR", "")
            if not toolchain_path and developer_path:
                toolchain_path = developer_path + "/Toolchains/XcodeDefault.xctoolchain"
            if toolchain_path:
                mappings.setdefault("/^toolchain", toolchain_path)

        def lldb_quoted(value):
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'

        # LLDB maps a breakpoint's path back through the first entry whose directory contains it, but the
        # compilers record the most specific directory and, for the same directory, the mapping Xcode passes
        # last: the SDK mappings, then the project ones, then `*_OTHER_PREFIX_MAPPINGS` such as `/^root`.
        xcode_aliases = ["/^sdk", "/^toolchain", "/^xcode", "/^src", "/^derived", "/^built", "/^workspace"]

        def compiler_precedence(mapping):
            alias, path = mapping
            passed_later = xcode_aliases.index(alias) if alias in xcode_aliases else len(xcode_aliases)
            return (-len(path.rstrip("/")), -passed_later, alias)

        \#(CachedModuleSymbolsPreparationScript.value)

        if mappings:
            arguments = " ".join(lldb_quoted(value) for mapping in sorted(mappings.items(), key=compiler_precedence) for value in mapping)
            # Xcode keeps one LLDB process across runs and sources this file into its global settings, so
            # appending would leave earlier runs' entries, including other checkouts', ahead of these.
            with open(sys.argv[1], "w", encoding="utf-8") as output:
                output.write("settings set target.source-map " + arguments + "\n")
        TUIST_SOURCE_MAP
        """#
    }
}

private struct DebuggerSourceMappingPlan: Encodable {
    let mappings: [[String]]
    let artifacts: [String]
    let nativeProducts: [String]
    let requiresLinkedDebugInformation: Bool
}

private struct DebuggerConfiguration {
    let lldbInitPath: AbsolutePath
    let initialLLDBInitFile: FileDescriptor
    let preAction: ExecutionAction
    let sourceMappingsFile: FileDescriptor?
}

private enum CachedModulesDebuggingGraphMapperError: Error {
    case missingProject(AbsolutePath)
    case ambiguousSourceMappings
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
