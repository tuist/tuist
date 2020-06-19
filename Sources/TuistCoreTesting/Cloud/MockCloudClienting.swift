import Foundation
import RxSwift
import TuistSupport

@testable import TuistCore

public final class MockCloudClienting<U>: CloudClienting {
    public init() {}

    public static func makeForSuccess(object: U, response: HTTPURLResponse) -> MockCloudClienting<U> {
        let mock = MockCloudClienting<U>()
        mock.configureForSuccess(object: object, response: response)
        return mock
    }

    public static func makeForError(error: Error) -> MockCloudClienting<U> {
        let mock = MockCloudClienting<U>()
        mock.configureForError(error: error)
        return mock
    }

    public var invokedRequest = false
    public var invokedRequestCount = 0
    public var invokedRequestParameter: HTTPResource<U, CloudResponseError>?
    public var invokedRequestParameterList = [HTTPResource<U, CloudResponseError>]()

    private var stubbedResponse: HTTPURLResponse?
    private var stubbedObject: U?
    private var stubbedError: Error?

    public func configureForError(error: Error) {
        stubbedError = error
        stubbedObject = nil
        stubbedResponse = nil
    }

    public func configureForSuccess(object: U, response: HTTPURLResponse) {
        stubbedError = nil
        stubbedObject = object
        stubbedResponse = response
    }

    public func request<T, E>(_ resource: HTTPResource<T, E>) -> Single<(object: T, response: HTTPURLResponse)> where E: Error {
        invokedRequest = true
        invokedRequestCount += 1
        invokedRequestParameter = resource as? HTTPResource<U, CloudResponseError>
        invokedRequestParameterList.append(invokedRequestParameter!)

        if let stubbedError = self.stubbedError {
            return Single.error(stubbedError)
        } else {
            guard let obj = stubbedObject as? T else { fatalError("This function input parameter type should equal to the class one") }
            return Single.just((obj, stubbedResponse!))
        }
    }
}
