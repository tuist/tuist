import Foundation
import TuistCore
import TSCBasic

class StaticLibWithResourcesGraphMapper: GraphMapping {
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        
        
        
        return (graph, sideEffects(graph))
    }
    
    fileprivate func sideEffects(_ graph: Graph) -> [SideEffectDescriptor] {
        graph.targets.flatMap({$0.value}).compactMap { (target) -> SideEffectDescriptor? in
            switch target.target.product {
            case .framework, .staticFramework, .staticLibrary, .dynamicLibrary:
                let content = """
import Foundation

extension Bundle {
}
"""
                return .file(.init(path: swiftFilePath(target: target), contents: content.data(using: .utf8), state: .present))
            default:
                return nil
            }
        }
    }
    
    fileprivate func swiftFilePath(target: TargetNode) -> AbsolutePath {
        target.project.path.appending(RelativePath("Derived/Resources/Bundle+\(target.target.name).swift"))
    }
    
}
