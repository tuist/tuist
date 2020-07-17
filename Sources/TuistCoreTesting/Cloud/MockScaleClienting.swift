import Foundation
import RxSwift
import TuistSupport

@testable import TuistCore

public enum MockScaleClientingError: Error {
    case mockedError
}

public final class MockScaleClienting<U, E: Error>: ScaleClienting {
    public init() {}

    public static func makeForSuccess(object: U, response: HTTPURLResponse) -> MockScaleClienting<U, E> {
        let mock = MockScaleClienting<U, E>()
        mock.configureForSuccess(object: object, response: response)
        return mock
    }

    public static func makeForError(error: E) -> MockScaleClienting<U, E> {
        let mock = MockScaleClienting<U, E>()
        mock.configureForError(error: error)
        return mock
    }

    public var invokedRequest = false
    public var invokedRequestCount = 0
    public var invokedRequestParameter: HTTPResource<U, E>?
    public var invokedRequestParameterList = [HTTPResource<U, E>]()

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

    public func request<T, Err>(_ resource: HTTPResource<T, Err>) -> Single<(object: T, response: HTTPURLResponse)> {
        invokedRequest = true
        invokedRequestCount += 1
        invokedRequestParameter = resource as? HTTPResource<U, E>
        invokedRequestParameterList.append(invokedRequestParameter!)

        if let stubbedError = self.stubbedError {
            return Single.error(stubbedError)
        } else {
            guard let obj = stubbedObject as? T else { fatalError("This function input parameter type should equal to the class one") }
            return Single.just((obj, stubbedResponse!))
        }
    }
}
