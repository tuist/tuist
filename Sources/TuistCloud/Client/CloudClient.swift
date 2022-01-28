import Foundation
import TuistCore
import TuistSupport

public class CloudClient: CloudClienting {
    // MARK: - Attributes

    let cloudHTTPRequestAuthenticator: CloudHTTPRequestAuthenticating

    // Use session without redirect to prevent redirects to be wrongly interpreted as successful responses.
    // For example, the `CacheRemoteStorage.exists` method would return true if the request is not authenticated and redirect is allowed.
    private var noRedirectDelegate: NoRedirectDelegate? // swiftlint:disable:this weak_delegate
    lazy var requestDispatcher: HTTPRequestDispatching = {
        noRedirectDelegate = NoRedirectDelegate()
        return HTTPRequestDispatcher(session: URLSession(
            configuration: .default,
            delegate: noRedirectDelegate,
            delegateQueue: nil
        ))
    }()

    // MARK: - Init

    public init(cloudHTTPRequestAuthenticator: CloudHTTPRequestAuthenticating = CloudHTTPRequestAuthenticator()) {
        self.cloudHTTPRequestAuthenticator = cloudHTTPRequestAuthenticator
    }

    // MARK: - Public

    public func request<T, E>(_ resource: HTTPResource<T, E>) async throws -> (object: T, response: HTTPURLResponse) {
        try await requestDispatcher.dispatch(resource: resourceWithHeaders(resource))
    }

    // MARK: - Fileprivate

    private func resourceWithHeaders<T, E>(_ resource: HTTPResource<T, E>) throws -> HTTPResource<T, E> {
        try resource.mappingRequest { request -> URLRequest in
            var request = request
            if request.allHTTPHeaderFields == nil { request.allHTTPHeaderFields = [:] }
            request.allHTTPHeaderFields?["Content-Type"] = "application/json;"
            return try self.cloudHTTPRequestAuthenticator.authenticate(request: request)
        }
    }
}

private class NoRedirectDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Swift.Void
    ) {
        // disable redirect
        completionHandler(nil)
    }
}
