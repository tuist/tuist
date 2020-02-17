import Foundation
import RxSwift
import TuistSupport
@testable import TuistEnvKit

public final class MockURLSessionScheduler: URLSessionScheduling {
    private var stubs: [URLRequest: (error: URLError?, data: Data?)] = [:]

    public init() {}

    public func stub(request: URLRequest, error: URLError?) {
        stubs[request] = (error: error, data: nil)
    }

    public func stub(request: URLRequest, data: Data?) {
        stubs[request] = (error: nil, data: data)
    }

    public func schedule(request: URLRequest) -> (error: Error?, data: Data?) {
        guard let stub = stubs[request] else {
            return (error: nil, data: nil)
        }
        return stub
    }

    public func single(request: URLRequest) -> Single<Data> {
        guard let stub = stubs[request] else {
            return Single.error(URLSessionSchedulerError.noData(request))
        }
        if let error = stub.error {
            return Single.error(error)
        } else if let data = stub.data {
            return Single.just(data)
        } else {
            return Single.error(URLSessionSchedulerError.noData(request))
        }
    }
}
