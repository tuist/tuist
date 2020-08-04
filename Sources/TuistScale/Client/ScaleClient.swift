import Foundation
import RxSwift
import TuistCore
import TuistSupport

public class ScaleClient: ScaleClienting {
    // MARK: - Attributes

    let scaleHTTPRequestAuthenticator: ScaleHTTPRequestAuthenticating
    let requestDispatcher: HTTPRequestDispatching

    // MARK: - Init

    public init(scaleHTTPRequestAuthenticator: ScaleHTTPRequestAuthenticating = ScaleHTTPRequestAuthenticator(),
                requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher())
    {
        self.scaleHTTPRequestAuthenticator = scaleHTTPRequestAuthenticator
        self.requestDispatcher = requestDispatcher
    }

    // MARK: - Public

    public func request<T, E>(_ resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> {
        Single<HTTPResource<T, E>>.create { (observer) -> Disposable in
            do {
                observer(.success(try self.resourceWithHeaders(resource)))
            } catch {
                observer(.error(error))
            }
            return Disposables.create()
        }.flatMap(requestDispatcher.dispatch)
    }

    // MARK: - Fileprivate

    private func resourceWithHeaders<T, E>(_ resource: HTTPResource<T, E>) throws -> HTTPResource<T, E> {
        try resource.mappingRequest { (request) -> URLRequest in
            var request = request
            if request.allHTTPHeaderFields == nil { request.allHTTPHeaderFields = [:] }
            request.allHTTPHeaderFields?["Content-Type"] = "application/json;"
            return try self.scaleHTTPRequestAuthenticator.authenticate(request: request)
        }
    }
}
