import Foundation
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockInfoPlistContentProvider: InfoPlistContentProviding {
    var contentArgs: [(graph: Graph, project: Project, target: Target, extendedWith: [String: InfoPlist.Value])] = []
    var contentStub: [String: Any]?

    func content(graph: Graph, project: Project, target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]? {
        contentArgs.append((graph: graph, project: project, target: target, extendedWith: extendedWith))
        return contentStub ?? [:]
    }
}
