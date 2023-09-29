import Combine
import Foundation

public enum HTTPRequestDispatcherError: LocalizedError, FatalError {
    case urlSessionError(URLRequest, Error)
    case parseError(URLRequest, Error)
    case invalidResponse(URLRequest)
    case serverSideError(URLRequest, Error, HTTPURLResponse)

    // MARK: - LocalizedError

    public var errorDescription: String? { description }

    // MARK: - FatalError

    public var description: String {
        switch self {
        case let .urlSessionError(request, error):
            return "Received a session error when performing \(request.descriptionForError): \(error.localizedDescription)"
        case let .parseError(request, error):
            return "Error parsing the network response of \(request.descriptionForError): \(error.localizedDescription)"
        case let .invalidResponse(request):
            return "Received unexpected response from the network when performing \(request.descriptionForError)"
        case let .serverSideError(request, error, response):
            return """
            Error returned by the server when performing \(request.descriptionForError):
              - URL: \(response.url!.absoluteString)
              - Code: \(response.statusCode)
              - Description: \(error.localizedDescription)
            """
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

    public func dispatch<T>(resource: HTTPResource<T, some Error>) async throws -> (object: T, response: HTTPURLResponse) {
        let request = resource.request()
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw HTTPRequestDispatcherError.invalidResponse(request)
            }
            switch response.statusCode {
            case 200 ..< 300:
                do {
                    let object = try resource.parse(data, response)
                    return (object: object, response: response)
                } catch {
                    throw HTTPRequestDispatcherError.parseError(request, error)
                }
            default: // Error
                let thrownError: Error
                do {
                    let parsedError = try resource.parseError(data, response)
                    thrownError = HTTPRequestDispatcherError.serverSideError(request, parsedError, response)
                } catch {
                    thrownError = HTTPRequestDispatcherError.parseError(request, error)
                }
                throw thrownError
            }
        } catch {
            if error is HTTPRequestDispatcherError {
                throw error
            } else {
                throw HTTPRequestDispatcherError.urlSessionError(request, error)
            }
        }
    }
}
