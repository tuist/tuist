import Foundation
import OpenCombine
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

    func publisher(request: URLRequest) -> OpenCombine.AnyPublisher<(data: Data, response: URLResponse), URLError> {
        guard let stub = stubs[request] else {
            return OpenCombine.Fail<(data: Data, response: URLResponse), URLError>(error: URLError(.badServerResponse))
                .eraseToAnyPublisher()
        }
        if let data = stub.data {
            let response = URLResponse()
            return OpenCombine.Just<(data: Data, response: URLResponse)>.init((data: data, response: response))
                .setFailureType(to: URLError.self)
                .eraseToAnyPublisher()
        } else if let error = stub.error {
            return OpenCombine.Fail<(data: Data, response: URLResponse), URLError>(error: error)
                .eraseToAnyPublisher()
        } else {
            return OpenCombine.Fail<(data: Data, response: URLResponse), URLError>(error: URLError(.badServerResponse))
                .eraseToAnyPublisher()
        }
    }
}
