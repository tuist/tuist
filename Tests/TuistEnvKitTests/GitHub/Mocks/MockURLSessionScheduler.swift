import Foundation
@testable import TuistEnvKit

final class MockURLSessionScheduler: URLSessionScheduling {
    private var stubs: [URLRequest: (error: URLError?, data: Data?)] = [:]

    func stub(request: URLRequest, error: URLError?) {
        stubs[request] = (error: error, data: nil)
    }

    func stub(request: URLRequest, data: Data?) {
        stubs[request] = (error: nil, data: data)
    }

    func schedule(request: URLRequest) -> (error: Error?, data: Data?) {
        guard let stub = stubs[request] else {
            return (error: nil, data: nil)
        }
        return stub
    }
}
