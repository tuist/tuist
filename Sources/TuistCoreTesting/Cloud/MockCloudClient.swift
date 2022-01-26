import Foundation
import TuistSupport

@testable import TuistCore

public enum MockCloudClientingError: Error {
    case mockedError
}

public final class MockCloudClient: CloudClienting {
    // MARK: Factories

    public var invokedRequest = false
    public var invokedRequestCount = 0
    public var invokedRequestParameterList = [Any]()

    private var stubbedResponse: HTTPURLResponse?
    private var stubbedObject: Any?
    private var stubbedError: Error?

    public var stubbedResponsePerURLRequest: [URLRequest: HTTPURLResponse] = [:]
    public var stubbedObjectPerURLRequest: [URLRequest: Any] = [:]
    public var stubbedErrorPerURLRequest: [URLRequest: Error] = [:]

    // MARK: Configurations

    public func mock(error: Error) {
        stubbedError = error
        stubbedObject = nil
        stubbedResponse = nil
    }

    public func mock(object: Any, response: HTTPURLResponse) {
        stubbedError = nil
        stubbedObject = object
        stubbedResponse = response
    }

    public func mock(
        responsePerURLRequest: [URLRequest: HTTPURLResponse] = [:],
        objectPerURLRequest: [URLRequest: Any] = [:],
        errorPerURLRequest: [URLRequest: Error] = [:]
    ) {
        stubbedError = nil
        stubbedObject = nil
        stubbedResponse = HTTPURLResponse.test()
        stubbedResponsePerURLRequest = responsePerURLRequest
        stubbedObjectPerURLRequest = objectPerURLRequest
        stubbedErrorPerURLRequest = errorPerURLRequest
    }

    // MARK: Public Interface

    public func request<T, Err: Error>(_ resource: HTTPResource<T, Err>) async throws -> (object: T, response: HTTPURLResponse) {
        invokedRequest = true
        invokedRequestCount += 1
        invokedRequestParameterList.append(resource)

        let urlRequest = resource.request()
        let errorCandidate = stubbedErrorPerURLRequest[urlRequest] ?? stubbedError
        if let error = errorCandidate {
            throw error
        } else {
            let objectCandidate = stubbedObjectPerURLRequest[urlRequest] ?? stubbedObject
            guard let object = objectCandidate as? T
            else {
                fatalError(
                    "This function input parameter type should be the same as the one provided in this object's initializer.\nReceived type: \(String(describing: objectCandidate.self))\nExpected type: \(T.self)"
                )
            }
            let responseCandidate = stubbedResponsePerURLRequest[urlRequest] ?? stubbedResponse
            return (object, responseCandidate!)
        }
    }
}
