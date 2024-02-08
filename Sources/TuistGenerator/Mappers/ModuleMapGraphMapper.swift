import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// A target mapper that enforces explicit dependneices by adding custom build directories
public struct ModuleMapGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) async throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)

        var graph = graph

        var sideEffects: [SideEffectDescriptor] = []
        var impartedSettings: [Target: SettingsDictionary] = [:]

        for target in try graphTraverser.allTargetsTopologicalSorted() {
            if target.project.isExternal {
                let (newSideEffects, newImpartedSettings) = mapExternal(target, graphTraverser: graphTraverser)
                sideEffects.append(contentsOf: newSideEffects)
                impartedSettings[target.target] = newImpartedSettings
            }
            
            for dependency in graphTraverser.directTargetDependencies(path: target.path, name: target.target.name) {
                guard let dependencyImpartedSettings = impartedSettings[dependency.target] else { continue }
                if let targetImpartedSettings = impartedSettings[target.target] {
                    impartedSettings[target.target] = targetImpartedSettings
                        .merging(
                            dependencyImpartedSettings,
                            uniquingKeysWith: {
                                switch ($0, $1) {
                                case let (.array(leftArray), .array(rightArray)):
                                    return SettingValue.array(leftArray + rightArray)
                                default:
                                    return $1
                                }
                            }
                        )
                } else {
                    impartedSettings[target.target] = dependencyImpartedSettings
                }
            }
        }
        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = project.targets.map { target in
                var target = target
                target.additionalFiles
                return target
                    .with(additionalSettings: impartedSettings[target] ?? [:])
            }

            return (projectPath, project)
        })
        return (graph, sideEffects)
    }

    private func mapExternal(_ graphTarget: GraphTarget, graphTraverser: GraphTraversing) -> ([SideEffectDescriptor], SettingsDictionary)  {
        var target = graphTarget.target
        guard
            let publicHeaders = target.headers?.public,
            !publicHeaders.isEmpty,
            target.settings?.base["MODULEMAP_FILE"] == nil
        else { return ([], [:]) }
        
        let umbrellaHeaderPath: AbsolutePath
        if
            let defaultUmbrellaHeader = publicHeaders.first(where: { $0.basename == "\(target.name).h" }) {
            umbrellaHeaderPath = defaultUmbrellaHeader
        } else {
            return ([], [:])
        }

//        let publicHeadersPath = potentialModule.path.appending(try RelativePath(validating: publicHeaderComponent))
        // TODO: Add condition for the following -> otherwise, we need to generate the umbrella header
        // If 'PublicHeadersDir/ModuleName.h' exists, then use it as the umbrella header.
        let moduleMapContent = """
        framework module \(target.name) {
          umbrella header "\(umbrellaHeaderPath.pathString)"

          export *
          module * { export * }
        }
        """
        
        let moduleMapPath = graphTarget.project.path.appending(
            components: [
                Constants.DerivedDirectory.name,
                Constants.DerivedDirectory.moduleMaps,
                "\(target.productName).modulemap",
            ]
        )
        
        let moduleMapSideEffect = SideEffectDescriptor.file(
            FileDescriptor(
                path: moduleMapPath,
                contents: moduleMapContent.data(using: .utf8)!
            )
        )
        
        return (
            [moduleMapSideEffect], 
            [
                "OTHER_SWIFT_FLAGS": .array(
                    [
                        "$(inherited)",
                        "-Xcc", "-fmodule-map-file=\(moduleMapPath.pathString)",
                    ]
                ),
                "HEADER_SEARCH_PATHS": .array(
                    [
                        "$(inherited)",
                        umbrellaHeaderPath.parentDirectory.parentDirectory.pathString,
                    ]
                )
            ]
        )
    }
}
