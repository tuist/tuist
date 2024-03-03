import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A target mapper that enforces explicit dependencies by adding custom build directories
public struct ExplicitDependencyGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) async throws -> (Graph, [SideEffectDescriptor]) {
        if !graph.packages.isEmpty {
            return (
                graph,
                []
            )
        }
        logger.debug("Transforming graph \(graph.name): Enforcing explicit dependencies")

        let graphTraverser = GraphTraverser(graph: graph)

        var graph = graph

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = project.targets.map { target in
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                let projectDebugConfigurations = project.settings.configurations.keys
                    .filter { $0.variant == .debug }
                    .map(\.name)

                let mappedTarget = map(
                    graphTarget,
                    graphTraverser: graphTraverser,
                    debugConfigurations: projectDebugConfigurations
                        .isEmpty ? [project.defaultDebugBuildConfigurationName] : projectDebugConfigurations
                )

                return mappedTarget
            }

            return (projectPath, project)
        })
        return (graph, [])
    }

    private func map(_ graphTarget: GraphTarget, graphTraverser: GraphTraversing, debugConfigurations: [String]) -> Target {
        let allTargetDependencies = graphTraverser.allTargetDependencies(
            path: graphTarget.path,
            name: graphTarget.target.name
        )
        let frameworkSearchPaths = allTargetDependencies
            .map(\.target.productName).map {
                "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)"
            }

        switch graphTarget.target.product {
        case .dynamicLibrary, .staticLibrary, .framework, .staticFramework, .bundle:
            break
        default:
            return graphTarget.target
        }

        var additionalSettings: SettingsDictionary = [
            "TARGET_BUILD_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
            "BUILT_PRODUCTS_DIR": "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)",
        ]

        if graphTarget.project.isExternal {
            additionalSettings["FRAMEWORK_SEARCH_PATHS"] = .array(["$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)"])
        } else if !frameworkSearchPaths.isEmpty {
            additionalSettings["FRAMEWORK_SEARCH_PATHS"] = .array(frameworkSearchPaths)
        }

        // Recursively find whether a graph targets needs to have "ENABLE_TESTING_SEARCH_PATHS" set to "YES"
        func needsEnableTestingSearchPaths(graphTarget: GraphTarget) -> Bool {
            guard let target = graphTraverser.target(
                path: graphTarget.path,
                name: graphTarget.target.name
            )?.target else {
                return false
            }

            if target.settings?.base.contains(where: { key, value in
                return key == "ENABLE_TESTING_SEARCH_PATHS" && value == .string("YES")
            }) ?? false {
                return true
            }

            let allTargetDependencies = graphTraverser.allTargetDependencies(
                path: graphTarget.path,
                name: graphTarget.target.name
            )

            guard !allTargetDependencies.isEmpty else {
                return false
            }

            var enable = false
            for dependency in allTargetDependencies {
                if needsEnableTestingSearchPaths(graphTarget: dependency) {
                    enable = true
                    break
                }
            }
            return enable
        }

        // If any dependency of this target has "ENABLE_TESTING_SEARCH_PATHS" set to "YES", it needs to be propagated
        // on the upstream target as well
        if needsEnableTestingSearchPaths(graphTarget: graphTarget) {
            additionalSettings["ENABLE_TESTING_SEARCH_PATHS"] = .string("YES")
        }

        var target = graphTarget.target
        target.settings = Settings(
            base: target.settings?.base ?? [:],
            baseDebug: additionalSettings,
            configurations: [:]
        )

        let copyBuiltProductsScript: String
        let builtProductsScriptInputPaths: [String]
        let builtProductsScriptOutputPaths: [String]

        switch target.product {
        case .staticLibrary:
            let (libScript, libInputPaths, libOutputPaths) = copyBuiltProductsToSharedDirectory(
                debugConfigurations: debugConfigurations,
                extensionName: "a",
                prefix: "lib"
            )
            let (moduleScript, moduleInputPaths, moduleOutputPaths) = copyBuiltProductsToSharedDirectory(
                debugConfigurations: debugConfigurations,
                extensionName: "swiftmodule"
            )
            copyBuiltProductsScript = [libScript, moduleScript].joined(separator: "\n")

            builtProductsScriptInputPaths = libInputPaths + moduleInputPaths
            builtProductsScriptOutputPaths = libOutputPaths + moduleOutputPaths
        case .dynamicLibrary:
            (
                copyBuiltProductsScript,
                builtProductsScriptInputPaths,
                builtProductsScriptOutputPaths
            ) = copyBuiltProductsToSharedDirectory(
                debugConfigurations: debugConfigurations,
                extensionName: "swiftmodule"
            )
        case .bundle:
            (
                copyBuiltProductsScript,
                builtProductsScriptInputPaths,
                builtProductsScriptOutputPaths
            ) = copyBuiltProductsToSharedDirectory(
                debugConfigurations: debugConfigurations,
                extensionName: "bundle"
            )
        case .framework, .staticFramework:
            (
                copyBuiltProductsScript,
                builtProductsScriptInputPaths,
                builtProductsScriptOutputPaths
            ) = copyBuiltProductsToSharedDirectory(
                debugConfigurations: debugConfigurations,
                extensionName: "framework"
            )
        default:
            return graphTarget.target
        }

        target = target.with(
            scripts: target.scripts + [
                TargetScript(
                    name: "Copy Built Products for Explicit Dependencies",
                    order: .post,
                    script: .embedded(
                        """
                        # This script copies built products into the shared directory to be available for app and other targets that don't have scoped directories
                        # If you try to archive any of the configurations seen in the output paths, the operation will fail due to `Multiple commands produce` error

                        \(copyBuiltProductsScript)
                        """
                    ),
                    inputPaths: builtProductsScriptInputPaths,
                    outputPaths: builtProductsScriptOutputPaths
                ),
            ]
        )
        return target
    }

    private func copyBuiltProductsToSharedDirectory(
        debugConfigurations: [String],
        extensionName: String,
        prefix: String = ""
    ) -> (String, [String], [String]) {
        let script = debugConfigurations.map {
            copyScript(for: $0, extensionName: extensionName, prefix: prefix)
        }
        .joined(separator: "\n")

        return (
            script,
            debugConfigurations.map {
                "$(BUILD_DIR)/\($0)$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)/\(prefix)$(PRODUCT_NAME).\(extensionName)"
            },
            debugConfigurations.map {
                "$(BUILD_DIR)/\($0)$(EFFECTIVE_PLATFORM_NAME)$(TARGET_BUILD_SUBPATH)/\(prefix)$(PRODUCT_NAME).\(extensionName)"
            }
        )
    }

    private func copyScript(
        for configuration: String,
        extensionName: String,
        prefix: String
    ) -> String {
        """
        FILE="$BUILD_DIR/\(configuration)$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/\(prefix)$PRODUCT_NAME.\(
            extensionName
        )"
        DESTINATION_FILE="$BUILD_DIR/\(configuration)$EFFECTIVE_PLATFORM_NAME$TARGET_BUILD_SUBPATH/\(prefix)$PRODUCT_NAME.\(
            extensionName
        )"
        if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi

        if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi
        """
    }
}
