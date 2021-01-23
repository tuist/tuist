import Foundation
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
@testable import TuistGenerator

final class MockInfoPlistContentProvider: InfoPlistContentProviding {
    var contentArgs: [(project: Project, target: Target, extendedWith: [String: InfoPlist.Value])] = []
    var contentStub: [String: Any]?

    func content(project: Project, target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]? {
        contentArgs.append((project: project, target: target, extendedWith: extendedWith))
        return contentStub ?? [:]
    }
}
