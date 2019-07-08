import Foundation
@testable import tuistenv

final class MockURLSessionScheduler: URLSessionScheduling {
    var scheduleStub: ((URLRequest) -> (Error?, Data?))?

    func schedule(request: URLRequest) -> (error: Error?, data: Data?) {
        return scheduleStub?(request) ?? (error: nil, data: nil)
    }
}
