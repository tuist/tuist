import Foundation
import ProjectAutomation

let graph: Graph
if CommandLine.arguments.contains("--path"),
   let path = CommandLine.arguments.last
{
    graph = try Tuist.graph(at: path)
} else {
    graph = try Tuist.graph()
}

let targets = graph.projects.values.flatMap(\.targets)
print("The current graph has the following targets: \(targets.map(\.name).joined(separator: " "))")
