import Foundation
import OpenCombine
import OpenCombineFoundation

protocol URLSessionScheduling: AnyObject {
    /// Schedules an URLSession request and returns the result synchronously.
    ///
    /// - Parameter request: request to be executed.
    /// - Returns: request's response.
    func schedule(request: URLRequest) -> (error: Error?, data: Data?)

    /// Returns a publisher that sends the given request. The publisher forwards the response data and error to the subscribers.
    /// - Parameter request: The request to be sent.
    func publisher(request: URLRequest) -> OpenCombine.AnyPublisher<(data: Data, response: URLResponse), URLError>
}

final class URLSessionScheduler: URLSessionScheduling {
    // MARK: - Constants

    /// The default request timeout.
    static let defaultRequestTimeout: Double = 3

    // MARK: - Attributes

    /// Session.
    private let session: URLSession

    /// Request timeout.
    private let requestTimeout: Double

    /// Initializes the client with the session.
    ///
    /// - Parameter session: url session.
    /// - Parameter requestTimeout: request timeout.
    init(session: URLSession = URLSession.shared,
         requestTimeout: Double = URLSessionScheduler.defaultRequestTimeout) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    func schedule(request: URLRequest) -> (error: Error?, data: Data?) {
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

    func publisher(request: URLRequest) -> OpenCombine.AnyPublisher<(data: Data, response: URLResponse), URLError> {
        URLSession.OCombine.DataTaskPublisher(request: request, session: session).eraseToAnyPublisher()
    }
}
