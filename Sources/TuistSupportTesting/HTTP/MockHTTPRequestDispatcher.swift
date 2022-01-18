import Combine
import Foundation
import TuistSupport

public class MockHTTPRequestDispatcher: HTTPRequestDispatching {
    public var requests: [URLRequest] = []

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) async throws -> (object: T, response: HTTPURLResponse) {
        if T.self != Void.self {
            fatalError(
                """
                MockHTTPRequestDispatcher only supports resources with Void as its generic value. \
                Use HTTPResource.noop from TuistSupportTesting.
                """
            )
        }
        requests.append(resource.request())
        let response = HTTPURLResponse()
        // swiftlint:disable:next force_cast
        return (object: () as! T, response: response)
    }
}
