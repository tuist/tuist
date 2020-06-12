import Foundation
import RxSwift

public enum HTTPRequestDispatcherError: LocalizedError {
    case urlSessionError(Error)
    case parseError(Error)
    case invalidResponse
    case serverSideError(Error, HTTPURLResponse)

    public var errorDescription: String? {
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
            return "Error returned by the server, code: \(response.statusCode). Error: \(error.localizedDescription)"
        }
    }
}

public protocol HTTPRequestDispatching {
    func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)>
}

public final class HTTPRequestDispatcher: HTTPRequestDispatching {
    let session: URLSession

    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> {
        Single.create { observer in
            let task = self.session.dataTask(with: resource.request(), completionHandler: { data, response, error in
                if let error = error {
                    observer(.error(HTTPRequestDispatcherError.urlSessionError(error)))
                } else if let data = data, let response = response as? HTTPURLResponse {
                    switch response.statusCode {
                    case 200 ..< 300:
                        do {
                            let object = try resource.parse(data, response)
                            observer(.success((object: object, response: response)))
                        } catch {
                            observer(.error(HTTPRequestDispatcherError.parseError(error)))
                        }
                    default: // Error
                        do {
                            let error = try resource.parseError(data, response)
                            observer(.error(HTTPRequestDispatcherError.serverSideError(error, response)))
                        } catch {
                            observer(.error(HTTPRequestDispatcherError.parseError(error)))
                        }
                    }
                } else {
                    observer(.error(HTTPRequestDispatcherError.invalidResponse))
                }
            })
            task.resume()

            return Disposables.create {
                task.cancel()
            }
        }
    }
}
