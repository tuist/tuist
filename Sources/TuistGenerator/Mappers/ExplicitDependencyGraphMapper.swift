import Foundation
import TuistCore
import TuistGraph
import TuistSupport
import TSCBasic

/// A target mapper that updates
public struct ExplicitDependencyGraphMapper: GraphMapping {
    public init() {}
    
    public func map(graph: Graph) async throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        
        if !graph.packages.isEmpty {
            return  (
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
            "FRAMEWORK_SEARCH_PATHS": .array(frameworkSearchPaths)
        ]

        if graphTarget.isExplicitnessEnforced {
            additionalSettings["TARGET_BUILD_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"

            additionalSettings["BUILT_PRODUCTS_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"
        }
        
        if graphTarget.target.product == .app {
            additionalSettings["DEPLOYMENT_LOCATION"] = "YES"
        }
        
        var target = graphTarget.target.with(
            additionalSettings: additionalSettings
        )
        
        if !graphTarget.isExplicitnessEnforced {
            let allDependencies = transitiveClosure([graphTarget]) { target in
                Array(
                    graphTraverser
                        .directTargetDependencies(
                            path: target.path,
                            name: target.target.name
                        )
                )
            }
            
            func moveScript(productNames: [String], extensionName: String, prefix: String = "", isDirectory: Bool = true) -> String {
                let existenceCheck = isDirectory ? "-d" : "-f"
                return """

                """
            }
            
            let copyProductsScript =
                    """
                    #!/bin/bash
                    
                    MOVED_PRODUCT_NAMES=( \(allDependencies.map(\.target.productName).joined(separator: " ")) )

                    for MOVED_PRODUCT in "${MOVED_PRODUCT_NAMES[@]}"
                    do
                        for FILE in $CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$MOVED_PRODUCT/*
                        do
                            DESTINATION_FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/$(basename $FILE)"
                            if [[ -d "$FILE" && ! -d "$DESTINATION_FILE" ]]; then
                                ln -s "$FILE" "$DESTINATION_FILE"
                            fi
                        
                            if [[ -f "$FILE" && ! -f "$DESTINATION_FILE" ]]; then
                                ln -s "$FILE" "$DESTINATION_FILE"
                            fi
                        done
                    done
                    """
            
            target = target.with(
                scripts: target.scripts + [
                    TargetScript(
                        name: "Copy Build Products",
                        order: .pre,
                        script: .embedded(copyProductsScript)
                    )
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
