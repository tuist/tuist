import Basic
import Foundation

@testable import TuistGenerator

extension TargetNode {
    static func test(project: Project = .test(),
                     target: Target = .test(),
                     dependencies: [GraphNode] = []) -> TargetNode {
        return TargetNode(project: project,
                          target: target,
                          dependencies: dependencies)
    }
}

extension FrameworkNode {
    static func test(path: AbsolutePath = "/Test.framework") -> FrameworkNode {
        return FrameworkNode(path: path)
    }
}

extension LibraryNode {
    static func test(path: AbsolutePath = "/libTest.a",
                     publicHeaders: AbsolutePath = "/TestHeaders/") -> LibraryNode {
        return LibraryNode(path: path, publicHeaders: publicHeaders)
    }
}
