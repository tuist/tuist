import Foundation
import TuistCloud
import TuistSupport
import RxSwift

public final class MockCloudClienting<U>: CloudClienting {

    public init(){}
    
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
    
    private var stubbedResponse: HTTPURLResponse? = nil
    private var stubbedObject: U? = nil
    private var stubbedError: Error? = nil
    
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
  
    public func request<T>(_ resource: HTTPResource<T, CloudResponseError>) -> Single<(object: T, response: HTTPURLResponse)> {
        invokedRequest = true
        invokedRequestCount += 1
        invokedRequestParameter = resource as? HTTPResource<U, CloudResponseError>
        invokedRequestParameterList.append(invokedRequestParameter!)

        if let stubbedError = self.stubbedError {
            return Single.error(stubbedError)
        } else {
            return Single.just((stubbedObject as! T, stubbedResponse!))
        }
    }
}
