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
        // Do not create the script, though
//        if movedProductNames.isEmpty {
//            return target.target
//        }

        let frameworkSearchPaths = graphTraverser.directTargetDependencies(
            path: graphTarget.path,
            name: graphTarget.target.name
        )
        .map(\.target.productName).map {
            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)"
        }

        var additionalSettings: SettingsDictionary = [
            "FRAMEWORK_SEARCH_PATHS": .array(frameworkSearchPaths),
        ]

        if graphTarget.isExplicitnessEnforced {
            additionalSettings["TARGET_BUILD_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"

            additionalSettings["BUILT_PRODUCTS_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"
        }

        if graphTarget.target.product == .app {
//            additionalSettings["DEPLOYMENT_LOCATION"] = "YES"
        }

        var target = graphTarget.target.with(
            additionalSettings: additionalSettings
        )

        if !graphTarget.isExplicitnessEnforced {
            let allDependencies = graphTraverser.allTargetDependencies(
                path: graphTarget.path,
                name: graphTarget.target.name
            )
            .subtracting(
                graphTraverser
                    .directTargetDependencies(
                        path: graphTarget.path,
                        name: graphTarget.target.name
                    )
                    .filter { !$0.isExplicitnessEnforced }
                    .flatMap {
                        graphTraverser
                            .directTargetDependencies(
                                path: $0.path,
                                name: $0.target.name
                            )
                    }
            )

            func explicitProducts(
                _ filterProduct: (GraphTarget) -> Bool,
                extensionName: String,
                prefix: String = ""
            ) -> (String, [String], [String]) {
                let productNames = allDependencies
                    .filter(filterProduct)
                    .map(\.target.productName)

                let script = """
                MOVED_PRODUCT_NAMES=( \(productNames.joined(separator: " ")) )

                for MOVED_PRODUCT in "${MOVED_PRODUCT_NAMES[@]}"
                do
                    FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$MOVED_PRODUCT/\(prefix)$MOVED_PRODUCT.\(extensionName)"
                    DESTINATION_FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/\(prefix)$MOVED_PRODUCT.\(extensionName)"
                    if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
                        ln -s "$FILE" "$DESTINATION_FILE"
                    fi

                    if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
                        ln -s "$FILE" "$DESTINATION_FILE"
                    fi
                done
                """

                return (
                    script,
                    productNames
                        .map {
                            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)/\(prefix)\($0).\(extensionName)"
                        },
                    productNames
                        .map {
                            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\(prefix)\($0).\(extensionName)"
                        }
                )
            }

            let (bundleScript, bundleInputPaths, bundleOutputPaths) = explicitProducts(
                { $0.target.product == .bundle },
                extensionName: "bundle"
            )

            let (frameworkScript, frameworkInputPaths, frameworkOutputPaths) = explicitProducts(
                { $0.target.product == .framework },
                extensionName: "framework"
            )

            let (libraryScript, libraryInputPaths, libraryOutputPaths) = explicitProducts(
                { $0.target.product == .staticLibrary || $0.target.product == .dynamicLibrary },
                extensionName: "swiftmodule"
            )

            let (staticLibraryScript, staticLibraryInputPaths, staticLibraryOutputPaths) = explicitProducts(
                { $0.target.product == .staticLibrary },
                extensionName: "a",
                prefix: "lib"
            )

            let copyProductsScript =
                """
                #!/bin/bash

                \(bundleScript)
                \(frameworkScript)
                \(libraryScript)
                \(staticLibraryScript)
                """

            let inputPaths = bundleInputPaths + frameworkInputPaths + libraryInputPaths + staticLibraryInputPaths

            if inputPaths.isEmpty {
                return target
            }

            target = target.with(
                scripts: target.scripts + [
                    TargetScript(
                        name: "Copy Build Products",
                        order: .pre,
                        script: .embedded(copyProductsScript),
                        inputPaths: inputPaths,
                        outputPaths: bundleOutputPaths + frameworkOutputPaths + libraryOutputPaths + staticLibraryOutputPaths
                    ),
                ]
            )
        }

        return target
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
