import Combine
import Foundation
import RxSwift
import TuistSupport

public class MockHTTPRequestDispatcher: HTTPRequestDispatching {
    public var requests: [URLRequest] = []

    public func dispatch<T, E>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> where E: Error {
        Single.create { observer in
            if T.self != Void.self {
                fatalError(
                    """
                    MockHTTPRequestDispatcher only supports resources with Void as its generic value. \
                    Use HTTPResource.noop from TuistSupportTesting.
                    """
                )
            }
            self.requests.append(resource.request())
            let response = HTTPURLResponse()
            // swiftlint:disable:next force_cast
            observer(.success((object: () as! T, response: response)))
            return Disposables.create()
        }
    }

    public func dispatch<T, E>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error>
        where E: Error
    {
        AnyPublisher.create { subscriber in
            if T.self != Void.self {
                fatalError(
                    """
                    MockHTTPRequestDispatcher only supports resources with Void as its generic value. \
                    Use HTTPResource.noop from TuistSupportTesting.
                    """
                )
            }
            self.requests.append(resource.request())
            let response = HTTPURLResponse()
            // swiftlint:disable:next force_cast
            subscriber.send((object: () as! T, response: response))
            subscriber.send(completion: .finished)
            return AnyCancellable {}
        }
    }
}
