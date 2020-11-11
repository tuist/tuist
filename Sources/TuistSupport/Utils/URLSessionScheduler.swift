import Foundation
import RxSwift

public enum URLSessionSchedulerError: FatalError {
    case httpError(status: HTTPStatusCode, response: URLResponse, request: URLRequest)

    public var type: ErrorType {
        switch self {
        case .httpError: return .abort
        }
    }

    public var description: String {
        switch self {
        case let .httpError(status, response, request):
            return "We got an error \(status) from the request \(response.url!) \(request.httpMethod!)"
        }
    }
}

public protocol URLSessionScheduling: AnyObject {
    /// Schedules an URLSession request and returns the result synchronously.
    ///
    /// - Parameter request: request to be executed.
    /// - Returns: request's response.
    func schedule(request: URLRequest) -> (error: Error?, data: Data?)

    /// Returns an observable that runs the given request and completes with either the data or an error.
    /// - Parameter request: URL request to be sent.
    /// - Returns: A Single instance to trigger the request.
    func single(request: URLRequest) -> Single<Data>
}

public final class URLSessionScheduler: URLSessionScheduling {
    // MARK: - Constants

    /// The default request timeout.
    public static let defaultRequestTimeout: Double = 3

    // MARK: - Attributes

    /// Session.
    private let session: URLSession

    /// Initializes the client with the session.
    ///
    /// - Parameter session: url session.
    /// - Parameter requestTimeout: request timeout.
    public init(requestTimeout: Double = URLSessionScheduler.defaultRequestTimeout) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        session = URLSession(configuration: configuration)
    }

    public func schedule(request: URLRequest) -> (error: Error?, data: Data?) {
        var data: Data?
        var error: Error?
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { sessionData, _, sessionError in
            data = sessionData
            error = sessionError
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (error: error, data: data)
    }

    public func single(request: URLRequest) -> Single<Data> {
        Single.create { (subscriber) -> Disposable in
            let task = self.session.dataTask(with: request) { data, response, error in
                let statusCode = (response as? HTTPURLResponse)?.statusCodeValue

                if let error = error {
                    subscriber(.error(error))
                } else if let statusCode = statusCode {
                    if !statusCode.isClientError, !statusCode.isServerError {
                        subscriber(.success(data ?? Data()))
                    } else {
                        subscriber(.error(URLSessionSchedulerError.httpError(status: statusCode,
                                                                             response: response!,
                                                                             request: request)))
                    }
                }
            }
            task.resume()
            return Disposables.create {
                task.cancel()
            }
        }
    }
}
