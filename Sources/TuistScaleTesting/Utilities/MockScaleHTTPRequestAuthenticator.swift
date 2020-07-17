import Foundation
import TuistSupport
import XCTest

@testable import TuistScale

final class MockScaleHTTPRequestAuthenticator: ScaleHTTPRequestAuthenticating {
    public init() {}

    public var authenticateStub: ((URLRequest) throws -> URLRequest)?
    func authenticate(request: URLRequest) throws -> URLRequest {
        if let authenticateStub = authenticateStub {
            return try authenticateStub(request)
        } else {
            return request
        }
    }
}
