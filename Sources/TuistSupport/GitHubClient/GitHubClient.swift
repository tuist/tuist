import Combine
import CombineExt
import Foundation

public protocol GitHubClienting {
    func deferred<T, E: Error>(resource: HTTPResource<T, E>) -> Deferred<Future<(object: T, response: HTTPURLResponse), Error>>
}

public final class GitHubClient: GitHubClienting {
    let requestDispatcher: HTTPRequestDispatching
    let gitEnvironment: GitEnvironmenting

    init(requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher(),
         gitEnvironment: GitEnvironmenting = GitEnvironment())
    {
        self.requestDispatcher = requestDispatcher
        self.gitEnvironment = gitEnvironment
    }

    public func deferred<T, E: Error>(resource: HTTPResource<T, E>) -> Deferred<Future<(object: T, response: HTTPURLResponse), Error>> {
        return Deferred {
            Future<(object: T, response: HTTPURLResponse), Error> { promise in
                _ = self.gitEnvironment.githubAuthentication().sink { completion in
                    if case let .failure(error) = completion {
                        promise(.failure(error))
                    }
                } receiveValue: { authentication in
                    var mappedResource: HTTPResource<T, E> = resource
                    do {
                        mappedResource = try self.authenticatedResource(resource: resource, authentication: authentication)
                    } catch {
                        promise(.failure(error))
                        return
                    }
                    _ = self.requestDispatcher.deferred(resource: mappedResource)
                        .sink { completion in
                            if case let .failure(error) = completion {
                                promise(.failure(error))
                            }
                        } receiveValue: { response in
                            promise(.success(response))
                        }
                }
            }
        }
    }

    // MARK: - Private

    private func authenticatedResource<T, E: Error>(resource: HTTPResource<T, E>, authentication: GitHubAuthentication?) throws -> HTTPResource<T, E> {
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
