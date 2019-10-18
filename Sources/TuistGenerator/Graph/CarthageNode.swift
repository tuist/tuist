import Basic
import Foundation
import TuistCore

class CarthageNode: GraphNode {
    
    let frameworkNode: FrameworkNode
    let targetNode: TargetNode?
    
    init(frameworkNode: FrameworkNode, targetNode: TargetNode?, path: AbsolutePath) {
        self.frameworkNode = frameworkNode
        self.targetNode = targetNode
        super.init(path: path, name: frameworkNode.name)
    }
    
}
