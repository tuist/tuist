import Foundation
import TSCBasic
import TuistSupport

enum HTTPClientError: FatalError {
    case clientError(URL, Error)
    case noData(URL)
    case copyFileError(AbsolutePath, Error)
    case missingResource(URL)

    /// Error type
    var type: ErrorType {
        switch self {
        case .clientError:
            return .abort
        case .noData:
            return .abort
        case .copyFileError:
            return .abort
        case .missingResource:
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
        case let .copyFileError(path, error):
            return "The file could not be copied into \(path.pathString): \(error.localizedDescription)"
        case let .missingResource(url):
            return "Couldn't locate resource downloaded from \(url.absoluteString)"
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

    /// Downloads the resource from the given URL into the file at the given path.
    ///
    /// - Parameters:
    ///   - url: URL to download the resource from.
    ///   - to: Path where the file should be downloaded.
    /// - Throws: An error if the dowload fails.
    func download(url: URL, to: AbsolutePath) throws
}

final class HTTPClient: HTTPClienting {
    // MARK: - Attributes

    /// URL session.
    fileprivate let session: URLSession = .shared

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
        session.dataTask(with: url) { responseData, _, responseError in
            data = responseData
            error = responseError
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = error {
            throw HTTPClientError.clientError(url, error)
        }
        guard let resultData = data else {
            throw HTTPClientError.noData(url)
        }
        return resultData
    }

    /// Downloads the resource from the given URL into the file at the given path.
    ///
    /// - Parameters:
    ///   - url: URL to download the resource from.
    ///   - to: Path where the file should be downloaded.
    /// - Throws: An error if the dowload fails.
    func download(url: URL, to: AbsolutePath) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var clientError: HTTPClientError?

        session.downloadTask(with: url) { downloadURL, _, error in
            defer { semaphore.signal() }
            if let error = error {
                clientError = HTTPClientError.clientError(url, error)
            } else if let downloadURL = downloadURL {
                let from = try! AbsolutePath(validating: downloadURL.path) // swiftlint:disable:this force_try
                do {
                    try FileHandler.shared.copy(from: from, to: to)
                } catch {
                    clientError = HTTPClientError.copyFileError(to, error)
                }
            } else {
                clientError = .missingResource(url)
            }
        }.resume()
        semaphore.wait()
        if let clientError = clientError {
            throw clientError
        }
    }
}
