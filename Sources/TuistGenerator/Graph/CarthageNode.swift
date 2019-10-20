import Basic
import Foundation
import TuistCore

class CarthageNode: GraphNode {
    
    let frameworkNode: FrameworkNode
    let targetNode: TargetNode
    
    init(frameworkNode: FrameworkNode, targetNode: TargetNode) {
        self.frameworkNode = frameworkNode
        self.targetNode = targetNode
        super.init(path: frameworkNode.path, name: frameworkNode.name)
    }
    
    var projectPath: AbsolutePath {
        return targetNode.path
    }
    
}
