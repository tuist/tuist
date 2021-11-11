import Foundation
import TuistSupport

public extension HTTPResource {
    static func void() -> HTTPResource<Void, E> {
        return HTTPResource<Void, E> {
            return URLRequest(url: URL(string: "https://test.tuist.io")!)
        } parse: { _, _ in
            ()
        } parseError: { _, _ in
            fatalError("The code execution shouldn't have reached this point")
        }
    }

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
