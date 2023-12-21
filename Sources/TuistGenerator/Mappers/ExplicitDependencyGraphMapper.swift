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
        let builtTargets = graphTraverser.directTargetDependencies(
            path: graphTarget.path,
            name: graphTarget.target.name
        )
            .filter(\.isBuilt)
        
        // Do not create the script, though
//        if movedProductNames.isEmpty {
//            return target.target
//        }
        
        let frameworkSearchPaths = builtTargets.map(\.target.productName).map {
            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)"
        }
        
        var additionalSettings: SettingsDictionary = [
            "FRAMEWORK_SEARCH_PATHS": .array(frameworkSearchPaths)
        ]

        additionalSettings["TARGET_BUILD_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"

        additionalSettings["BUILT_PRODUCTS_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"
        
        var target = graphTarget.target.with(
            additionalSettings: additionalSettings
        )
        
        if !graphTarget.isBuilt {
            let allDependencies = transitiveClosure([graphTarget]) { target in
                Array(
                    graphTraverser
                        .directTargetDependencies(
                            path: target.path,
                            name: target.target.name
                        )
                )
            }
            let movedFrameworkProductNames = allDependencies
                .filter { $0.target.product.isFramework }
                .map(\.target.productName)
            
            let movedLibraryProductNames = allDependencies
                .filter { $0.target.product == .staticLibrary || $0.target.product == .dynamicLibrary || $0.target.product == .app }
                .map(\.target.productName)
            
            let movedStaticLibraryProductNames = allDependencies
                .filter { $0.target.product == .staticLibrary }
                .map(\.target.productName)
            
            let moveBundleScript = moveScript(
                productNames: allDependencies
                    .filter { $0.target.product == .bundle }
                    .map(\.target.productName),
                extensionName: "bundle"
            )
            
            func moveScript(productNames: [String], extensionName: String, prefix: String = "", isDirectory: Bool = true) -> String {
                let existenceCheck = isDirectory ? "-d" : "-f"
                return """
                MOVED_PRODUCT_NAMES=( \(productNames.joined(separator: " ")) )

                for MOVED_PRODUCT in "${MOVED_PRODUCT_NAMES[@]}"
                do
                    BUILT_FRAMEWORK_FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$MOVED_PRODUCT/\(prefix)$MOVED_PRODUCT.\(extensionName)"
                    DESTINATION_FILE="$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/\(prefix)$MOVED_PRODUCT.\(extensionName)"
                    if [[ \(existenceCheck) "$BUILT_FRAMEWORK_FILE" && ! \(existenceCheck) "$DESTINATION_FILE" ]]; then
                        ln -s "$BUILT_FRAMEWORK_FILE" "$DESTINATION_FILE"
                    fi
                done
                """
            }
            
            let copyProductsScript =
                    """
                    #!/bin/bash
                    
                    \(moveScript(productNames: movedFrameworkProductNames, extensionName: "framework"))
                    \(moveScript(productNames: movedLibraryProductNames, extensionName: "swiftmodule"))
                    \(moveScript(productNames: movedStaticLibraryProductNames, extensionName: "a", prefix: "lib", isDirectory: false))
                    \(moveBundleScript)
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
    fileprivate var isBuilt: Bool {
        switch target.product {
        case .dynamicLibrary, .staticLibrary, .framework, .staticFramework, .bundle:
            return true
        default:
            return false
        }
    }
}
