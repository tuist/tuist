import Foundation
import TSCBasic

struct ValueGraph {
    let projects: [AbsolutePath: Project]
    let packages: [AbsolutePath: [String: Package]]
    let targets: [AbsolutePath: [String: Target]]
    let dependencies: [ValueGraphDependency: ValueGraphDependency]
}
