import Foundation
import TuistSupport

public extension HTTPResource {
    static func noop() -> HTTPResource<Void, Error> {
        return HTTPResource<Void, Error> {
            return URLRequest(url: URL(string: "https://test.tuist.io")!)
        } parse: { _, _ in
            ()
        } parseError: { _, _ in
            TestError("noop HTTPResource")
        }
    }
}
