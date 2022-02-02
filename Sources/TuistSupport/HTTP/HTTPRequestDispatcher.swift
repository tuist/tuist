import Combine
import Foundation

public enum HTTPRequestDispatcherError: LocalizedError, FatalError {
    case urlSessionError(Error)
    case parseError(Error)
    case invalidResponse
    case serverSideError(Error, HTTPURLResponse)

    // MARK: - LocalizedError

    public var errorDescription: String? { description }

    // MARK: - FatalError

    public var description: String {
        switch self {
        case let .urlSessionError(error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "Received a session error."
            }
        case let .parseError(error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "Error parsing the network response."
            }
        case .invalidResponse: return "Received unexpected response from the network."
        case let .serverSideError(error, response):
            let url: URL = response.url!
            if let error = error as? LocalizedError {
                return """
                Error returned by the server:
                  - URL: \(url.absoluteString)
                  - Code: \(response.statusCode)
                  - Description: \(error.localizedDescription)
                """
            } else {
                return """
                Error returned by the server:
                  - URL: \(url.absoluteString)
                  - Code: \(response.statusCode)
                """
            }
        }
    }

    public var type: ErrorType {
        switch self {
        case .urlSessionError: return .bug
        case .parseError: return .abort
        case .invalidResponse: return .bug
        case .serverSideError: return .bug
        }
    }
}

public protocol HTTPRequestDispatching {
    func dispatch<T, E: Error>(resource: HTTPResource<T, E>) async throws -> (object: T, response: HTTPURLResponse)
}

public final class HTTPRequestDispatcher: HTTPRequestDispatching {
    let session: URLSession

    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) async throws -> (object: T, response: HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: resource.request())
            guard let response = response as? HTTPURLResponse else {
                throw HTTPRequestDispatcherError.invalidResponse
            }
            switch response.statusCode {
            case 200 ..< 300:
                do {
                    let object = try resource.parse(data, response)
                    return (object: object, response: response)
                } catch {
                    throw HTTPRequestDispatcherError.parseError(error)
                }
            default: // Error
                let thrownError: Error
                do {
                    let parsedError = try resource.parseError(data, response)
                    thrownError = HTTPRequestDispatcherError.serverSideError(parsedError, response)
                } catch {
                    thrownError = HTTPRequestDispatcherError.parseError(error)
                }
                throw thrownError
            }
        } catch {
            if error is HTTPRequestDispatcherError {
                throw error
            } else {
                throw HTTPRequestDispatcherError.urlSessionError(error)
            }
        }
    }
}
