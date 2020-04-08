import Foundation
import TuistSupport

final class MockVersionsFetcher: VersionsFetching {
    public init() {}

    var fetchStub: Versions?
    func fetch() throws -> Versions {
        if let fetchStub = fetchStub {
            return fetchStub
        } else {
            return Versions.test()
        }
    }
}
