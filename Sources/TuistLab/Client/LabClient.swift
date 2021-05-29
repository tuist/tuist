import Foundation
import RxSwift
import TuistCore
import TuistSupport

public class LabClient: LabClienting {
    // MARK: - Attributes

    let labHTTPRequestAuthenticator: LabHTTPRequestAuthenticating
    let requestDispatcher: HTTPRequestDispatching

    // MARK: - Init

    public init(labHTTPRequestAuthenticator: LabHTTPRequestAuthenticating = LabHTTPRequestAuthenticator(),
                requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher())
    {
        self.labHTTPRequestAuthenticator = labHTTPRequestAuthenticator
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
            return try self.labHTTPRequestAuthenticator.authenticate(request: request)
        }
    }
}
