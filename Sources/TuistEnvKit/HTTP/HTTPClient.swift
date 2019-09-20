import Basic
import Foundation
import TuistCore

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

    /// Downloads the resource from the given URL into the passed directory.
    ///
    /// - Parameters:
    ///   - url: URL to download the resource from.
    ///   - into: Directory where the resource should be placed.
    /// - Throws: An error if the dowload fails.
    func download(url: URL, into: AbsolutePath) throws
}

final class HTTPClient: HTTPClienting {
    // MARK: - Attributes

    /// URL session.
    let session: URLSession = .shared
    let fileHandler: FileHandling = FileHandler.shared

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

    /// Downloads the resource from the given URL into the passed directory.
    ///
    /// - Parameters:
    ///   - url: URL to download the resource from.
    ///   - into: Directory where the resource should be placed.
    /// - Throws: An error if the dowload fails.
    func download(url: URL, into: AbsolutePath) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var clientError: HTTPClientError?

        session.downloadTask(with: url) { downloadURL, _, error in
            if let error = error {
                clientError = HTTPClientError.clientError(url, error)
                semaphore.signal()
            } else if let downloadURL = downloadURL {
                let from = AbsolutePath(downloadURL.absoluteString)
                let to = into.appending(component: from.components.last!)
                do {
                    try self.fileHandler.copy(from: from, to: to)
                    semaphore.signal()
                } catch {
                    clientError = HTTPClientError.copyFileError(to, error)
                    semaphore.signal()
                }
            } else {
                clientError = .missingResource(url)
                semaphore.signal()
            }
        }
        semaphore.wait()
        if let clientError = clientError {
            throw clientError
        }
    }
}
