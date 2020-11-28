import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistSigning
import TSCBasic

/// It defines an interface for providing the mappers to be used for a specific configuration.
protocol GraphMapperProviding {
    /// Returns a list of mappers to be used for a specific configuration.
    /// - Parameter config: Project's configuration.
    func mapper(config: Config) -> GraphMapping
}

final class GraphMapperProvider: GraphMapperProviding {
    init() {}
    
    func mapper(config: Config) -> GraphMapping {
        SequentialGraphMapper(mappers(config: config))
    }
    
    func mappers(config _: Config) -> [GraphMapping] {
        var mappers: [GraphMapping] = []
        mappers.append(UpdateWorkspaceProjectsGraphMapper())
        return mappers
    }
}
//
//import TuistSupport
//
//final class AutomationGraphMapperProvider: GraphMapperProviding {
//    private let graphMapperProvider: GraphMapperProviding
//    private let temporaryDirectory: AbsolutePath
//    
//    init(
//        temporaryDirectory: AbsolutePath,
//        graphMapperProvider: GraphMapperProviding = GraphMapperProvider()
//    ) {
//        self.temporaryDirectory = temporaryDirectory
//        self.graphMapperProvider = graphMapperProvider
//    }
//    
//    func mapper(config: Config) -> GraphMapping {
//        var mappers: [GraphMapping] = []
//        mappers.append(AutomationPathGraphMapper(temporaryDirectory: temporaryDirectory))
//        mappers.append(graphMapperProvider.mapper(config: config))
//        
//        return SequentialGraphMapper(mappers)
//    }
//}
//
//final class AutomationPathGraphMapper: GraphMapping {
//    private let temporaryDirectory: AbsolutePath
//    
//    init(
//        temporaryDirectory: AbsolutePath
//    ) {
//        self.temporaryDirectory = temporaryDirectory
//    }
//    
//    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
//        var workspace = graph.workspace
//        workspace.path = temporaryDirectory
//        return
//            (
//                graph
//                    .with(
//                        projects: graph.projects.map {
//                            var project = $0
//                            project.sourceRootPath = temporaryDirectory
//                            project.xcodeProjPath = temporaryDirectory
//                                .appending(component: project.xcodeProjPath.basename)
//                            return project
//                        }
//                    )
//                    .with(
//                        workspace: workspace
//                    ),
//                []
//            )
//    }
//}
