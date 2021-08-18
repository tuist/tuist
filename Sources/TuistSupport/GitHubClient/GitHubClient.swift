import Combine
import CombineExt
import Foundation

public protocol GitHubClienting {
    func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error>
}

public final class GitHubClient: GitHubClienting {
    let requestDispatcher: HTTPRequestDispatching
    let gitEnvironment: GitEnvironmenting

    public convenience init() {
        self.init(
            requestDispatcher: HTTPRequestDispatcher(),
            gitEnvironment: GitEnvironment()
        )
    }

    init(requestDispatcher: HTTPRequestDispatching,
         gitEnvironment: GitEnvironmenting)
    {
        self.requestDispatcher = requestDispatcher
        self.gitEnvironment = gitEnvironment
    }

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error> {
        gitEnvironment.githubAuthentication()
            .flatMap { (authentication: GitHubAuthentication?) -> AnyPublisher<HTTPResource<T, E>, Error> in
                do {
                    return AnyPublisher(value: try self.authenticatedResource(resource: resource, authentication: authentication))
                } catch {
                    return AnyPublisher(error: error)
                }
            }
            .flatMap { (resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error> in
                self.requestDispatcher.dispatch(resource: resource)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    private func authenticatedResource<T, E: Error>(
        resource: HTTPResource<T, E>,
        authentication: GitHubAuthentication?
    ) throws -> HTTPResource<T, E> {
        return try resource.mappingRequest { (request: URLRequest) -> URLRequest in
            var request = request
            var headers: [String: String]! = request.allHTTPHeaderFields
            if headers == nil { headers = [:] }
            if let authentication = authentication {
                switch authentication {
                case let .credentials(credentials):
                    let data = "\(credentials.username):\(credentials.password)".data(using: String.Encoding.utf8)!
                    let encodedString = data.base64EncodedString()
                    headers["Authorization"] = "Basic \(encodedString)"
                case let .token(token):
                    headers["Authorization"] = "token \(token)"
                }
            }
            headers["Accept"] = "application/vnd.github.v3+json"
            request.allHTTPHeaderFields = headers
            return request
        }
    }
}
