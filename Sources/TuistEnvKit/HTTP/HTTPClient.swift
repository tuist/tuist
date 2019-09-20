import Foundation
import TuistCore

enum HTTPClientError: FatalError {
    case clientError(URL, Error)
    case noData(URL)

    /// Error type
    var type: ErrorType {
        switch self {
        case .clientError:
            return .abort
        case .noData:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .clientError(url, error):
            return "The request to \(url.absoluteString) errored with: \(error.localizedDescription)"
        case let .noData(url):
            return "The request to \(url.absoluteString) returned no data"
        }
    }
}

protocol HTTPClienting {
    /// Fetches the content from the given URL and returns it as a data.
    ///
    /// - Parameter url: URL to download the resource from.
    /// - Returns: Response body as a data.
    /// - Throws: An error if the request fails.
    func read(url: URL) throws -> Data
}

final class HTTPClient: HTTPClienting {
    // MARK: - Attributes

    /// URL session.
    let session: URLSession = .shared

    // MARK: - HTTPClienting

    /// Fetches the content from the given URL and returns it as a data.
    ///
    /// - Parameter url: URL to download the resource from.
    /// - Returns: Response body as a data.
    /// - Throws: An error if the request fails.
    func read(url: URL) throws -> Data {
        var data: Data?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: url) { _data, _, _error in
            data = _data
            error = _error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = error {
            throw HTTPClientError.clientError(url, error)
        } else if let data = data {
            return data
        } else {
            throw HTTPClientError.noData(url)
        }
    }
}
