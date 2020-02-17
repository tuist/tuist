import Foundation
import RxSwift

public enum URLSessionSchedulerError: FatalError {
    case noData(URLRequest)

    public var type: ErrorType {
        switch self {
        case .noData: return .abort
        }
    }

    public var description: String {
        switch self {
        case let .noData(request):
            if let url = request.url?.absoluteString {
                return "An HTTP request to \(url) returned no data"
            } else {
                return "An HTTP request unexpectedly returned no data"
            }
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

    /// Request timeout.
    private let requestTimeout: Double

    /// Initializes the client with the session.
    ///
    /// - Parameter session: url session.
    /// - Parameter requestTimeout: request timeout.
    public init(session: URLSession = URLSession.shared,
                requestTimeout: Double = URLSessionScheduler.defaultRequestTimeout) {
        self.session = session
        self.requestTimeout = requestTimeout
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
        _ = semaphore.wait(timeout: .now() + 3)
        return (error: error, data: data)
    }

    public func single(request: URLRequest) -> Single<Data> {
        Single.create { (subscriber) -> Disposable in
            let task = self.session.dataTask(with: request) { data, _, error in
                if let data = data {
                    subscriber(.success(data))
                } else if let error = error {
                    subscriber(.error(error))
                } else {
                    subscriber(.error(URLSessionSchedulerError.noData(request)))
                }
            }
            task.resume()
            return Disposables.create {
                task.cancel()
            }
        }
    }
}
