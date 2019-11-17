import Foundation
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockInfoPlistContentProvider: InfoPlistContentProviding {
    var contentArgs: [(target: Target, extendedWith: [String: InfoPlist.Value])] = []
    var contentStub: [String: Any]?

    func content(target: Target, extendedWith: [String: InfoPlist.Value]) -> [String: Any]? {
        contentArgs.append((target: target, extendedWith: extendedWith))
        return contentStub ?? [:]
    }
}
