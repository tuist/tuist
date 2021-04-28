import Foundation
@testable import TuistSupport

public final class MockHTTPRedirectListener: HTTPRedirectListening {
    public init() {}

    public var listenStub: ((UInt16, String, String, URL) -> Swift.Result<[String: String]?, HTTPRedirectListenerError>)?

    public func listen(
        port: UInt16,
        path: String,
        redirectMessage: String,
        logoURL: URL
    ) -> Swift.Result<[String: String]?, HTTPRedirectListenerError> {
        if let listenStub = listenStub {
            return listenStub(port, path, redirectMessage, logoURL)
        } else {
            return Result.failure(.httpServer(TestError("non-stubbed called to listen")))
        }
    }
}
