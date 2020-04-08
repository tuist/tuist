import Foundation
import TuistSupport

final class MockVersionsFetcher: VersionsFetching {
    var fetchStub: Versions?
    func fetch() throws -> Versions {
        if let fetchStub = fetchStub {
            return fetchStub
        } else {
            return Versions.test()
        }
    }
}
