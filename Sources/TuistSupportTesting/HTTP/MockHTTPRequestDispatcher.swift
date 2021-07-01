import Combine
import Foundation
import RxSwift
import TuistSupport

public class MockHTTPRequestDispatcher: HTTPRequestDispatching {
    public var requests: [URLRequest] = []

    public func dispatch<T, E>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> where E: Error {
        return Single.create { observer in
            if T.self != Void.self {
                fatalError("MockHTTPRequestDispatcher only supports resources with Void as its generic value. Use HTTPResource.noop from TuistSupportTesting.")
            }
            self.requests.append(resource.request())
            let response = HTTPURLResponse()
            // swiftlint:disable:next force_cast
            observer(.success((object: () as! T, response: response)))
            return Disposables.create()
        }
    }

    public func deferred<T, E>(resource: HTTPResource<T, E>) -> Deferred<Future<(object: T, response: HTTPURLResponse), Error>> where E: Error {
        return Deferred {
            Future<(object: T, response: HTTPURLResponse), Error> { promise in
                if T.self != Void.self {
                    fatalError("MockHTTPRequestDispatcher only supports resources with Void as its generic value. Use HTTPResource.noop from TuistSupportTesting.")
                }
                self.requests.append(resource.request())
                let response = HTTPURLResponse()
                // swiftlint:disable:next force_cast
                promise(.success((object: () as! T, response: response)))
            }
        }
    }
}
