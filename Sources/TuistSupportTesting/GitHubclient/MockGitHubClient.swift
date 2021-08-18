import Combine
import CombineExt
import Foundation
import TuistSupport

public class MockGitHubClient: GitHubClienting {
    public var invokedDispatch = false
    public var invokedDispatchCount = 0
    public var invokedDispatchParameters: (resource: HTTPResource<Any, Error>, Void)?
    public var invokedDispatchParametersList = [(resource: HTTPResource<Any, Error>, Void)]()
    public var stubbedResources: [URLRequest: Result<Any, Error>] = [:]

    public init() {}

    public func dispatch<T, E: Error>(resource: HTTPResource<T, E>) -> AnyPublisher<(object: T, response: HTTPURLResponse), Error> {
        invokedDispatch = true
        invokedDispatchCount += 1
        invokedDispatchParameters = (resource.eraseToAnyResource(), ())
        invokedDispatchParametersList.append((resource.eraseToAnyResource(), ()))
        let request = resource.request()
        guard let stubbedResponse = stubbedResources[request] else {
            return AnyPublisher(error: TestError("Received request \(request) that hasn't been stubbed"))
        }
        switch stubbedResponse {
        case let .success(value):
            if let value = value as? T {
                return AnyPublisher(value: (object: value, response: HTTPURLResponse()))
            } else {
                fatalError("Resource stubbed with an invalid resource type.")
            }
        case let .failure(error):
            return AnyPublisher(error: error)
        }
    }

    public func stub<T, E: Error>(_ resource: HTTPResource<T, E>, result: Result<T, E>) {
        let request = resource.request()
        switch result {
        case let .success(value):
            stubbedResources[request] = .success(value)
        case let .failure(error):
            stubbedResources[request] = .failure(error)
        }
    }
}
