import Foundation
import ProjectAutomation

let graph = try Tuist.graph()
let targets = graph.projects.values.flatMap(\.targets)
print("The current graph has the following targets: \(targets.map(\.name).joined(separator: " "))")
