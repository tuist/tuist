import Foundation
import TuistSupport

extension HTTPResource {
    public static func void() -> HTTPResource<Void, E> {
        HTTPResource<Void, E> {
            URLRequest(url: URL(string: "https://test.tuist.io")!)
        } parse: { _, _ in
            ()
        } parseError: { _, _ in
            fatalError("The code execution shouldn't have reached this point")
        }
    }

    public static func noop() -> HTTPResource<Void, Error> {
        HTTPResource<Void, Error> {
            URLRequest(url: URL(string: "https://test.tuist.io")!)
        } parse: { _, _ in
            ()
        } parseError: { _, _ in
            TestError("noop HTTPResource")
        }
    }
}
