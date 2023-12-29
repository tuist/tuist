import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A target mapper that updates
public struct ExplicitDependencyGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) async throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)

        if !graph.packages.isEmpty {
            return (
                graph,
                []
            )
        }

        var graph = graph

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = project.targets.map { target in
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)

                let mappedTarget = map(graphTarget, graphTraverser: graphTraverser)

                return mappedTarget
            }

            return (projectPath, project)
        })
        return (graph, [])
    }

    private func map(_ graphTarget: GraphTarget, graphTraverser: GraphTraversing) -> Target {
        let allTargetDependencies = graphTraverser.allTargetDependencies(
            path: graphTarget.path,
            name: graphTarget.target.name
        )
        let frameworkSearchPaths = allTargetDependencies
            .map(\.target.productName).map {
                "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)"
            }

        if !graphTarget.isExplicitnessEnforced {
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

        var target = graphTarget.target.with(
            additionalSettings: additionalSettings
        )

        let isExternal = graphTarget.project.isExternal

        let copyBuiltProductsScript: String
        let builtProductsScriptInputPaths: [String]
        let builtProductsScriptOutputPaths: [String]

        switch target.product {
        case .staticLibrary:
            let (libScript, libInputPaths, libOutputPaths) = copyBuiltProductsToSharedDirectory(
                isExternal: isExternal,
                extensionName: "a",
                prefix: "lib"
            )
            let (moduleScript, moduleInputPaths, moduleOutputPaths) = copyBuiltProductsToSharedDirectory(
                isExternal: isExternal,
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
                isExternal: isExternal,
                extensionName: "swiftmodule"
            )
        case .bundle:
            (
                copyBuiltProductsScript,
                builtProductsScriptInputPaths,
                builtProductsScriptOutputPaths
            ) = copyBuiltProductsToSharedDirectory(
                isExternal: isExternal,
                extensionName: "bundle"
            )
        case .framework, .staticFramework:
            (
                copyBuiltProductsScript,
                builtProductsScriptInputPaths,
                builtProductsScriptOutputPaths
            ) = copyBuiltProductsToSharedDirectory(
                isExternal: isExternal,
                extensionName: "framework"
            )
        default:
            return graphTarget.target
        }

        target = target.with(
            scripts: target.scripts + [
                TargetScript(
                    name: "Copy Built Products",
                    order: .post,
                    script: .embedded(copyBuiltProductsScript),
                    inputPaths: builtProductsScriptInputPaths,
                    outputPaths: builtProductsScriptOutputPaths
                ),
            ]
        )

        return target
    }

    private func copyBuiltProductsToSharedDirectory(
        isExternal _: Bool,
        extensionName: String,
        prefix: String = ""
    ) -> (String, [String], [String]) {
        let script = """
        FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/\(prefix)$PRODUCT_NAME.\(extensionName)"
        DESTINATION_FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/\(prefix)$PRODUCT_NAME.\(extensionName)"
        if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi

        if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
            ln -s "$FILE" "$DESTINATION_FILE"
        fi
        """

        return (
            script,
            ["$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)/\(prefix)$(PRODUCT_NAME).\(extensionName)"],
            ["$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\(prefix)$(PRODUCT_NAME).\(extensionName)"]
        )
    }
}

extension GraphTarget {
    fileprivate var isExplicitnessEnforced: Bool {
        switch target.product {
        case .dynamicLibrary, .staticLibrary, .framework, .staticFramework, .bundle:
            return true
        default:
            return false
        }
    }
}
