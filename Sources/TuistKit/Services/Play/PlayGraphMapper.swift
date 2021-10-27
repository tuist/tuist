import Foundation
import TuistCore
import TuistGraph
import TSCBasic

class PlayGraphMapper: GraphMapping {
    let temporaryDirectory: AbsolutePath
    let targetName: String
    
    init(targetName: String, temporaryDirectory: AbsolutePath) {
        self.targetName = targetName
        self.temporaryDirectory = temporaryDirectory
    }
    
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        var graph = graph
        graph.workspace.xcWorkspacePath = temporaryDirectory.appending(component: graph.workspace.xcWorkspacePath.basename)
        graph.projects = graph.projects.reduce(into: [AbsolutePath: Project](), { projects, value in
            var project = value.value
            let mappedXcodeProjPath = temporaryDirectory.appending(component: project.xcodeProjPath.basename)
            project.xcodeProjPath = mappedXcodeProjPath
            projects[value.key] = project
        })
    
        let target = graph.targets.values.flatMap({ $0.values }).first(where: { $0.name == targetName })
        let targetPlatform = target!.platform.rawValue
        
        let playgroundPath = temporaryDirectory.appending(component: "\(self.targetName).playground")
        graph.workspace = graph.workspace.adding(files: [playgroundPath])

        let contentXCPlaygroundPath = playgroundPath.appending(component: "contents.xcplayground")
        let contentsSwiftPath = playgroundPath.appending(component: "Contents.swift")
        
        let xcplaygroundContent = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <playground version='5.0' target-platform='\(targetPlatform)' buildActiveScheme='true' executeOnSourceChanges='false' importAppTypes='true'>
            <timeline fileName='timeline.xctimeline'/>
        </playground>
        """
        let contentsSwiftContent = """
        import Foundation
        import \(targetName)
        
        print("Hello \(targetName)")
        """
        var sideEffects: [SideEffectDescriptor] = []
        sideEffects.append(.directory(.init(path: playgroundPath, state: .present)))
        sideEffects.append(.file(.init(path: contentXCPlaygroundPath, contents: xcplaygroundContent.data(using: .utf8), state: .present)))
        sideEffects.append(.file(.init(path: contentsSwiftPath, contents: contentsSwiftContent.data(using: .utf8), state: .present)))

        return (graph, sideEffects)
    }
    
    
}
