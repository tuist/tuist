import Basic
import Foundation
import Signals
import Swifter

public protocol HTTPRedirectListening: Any {
    /// Starts an HTTP server at the given port and blocks the process until a request is sent to the given path.
    /// - Parameters:
    ///   - port: Port for the HTTP server.
    ///   - path: Path we are expecting the browser to redirect the user to.
    ///   - redirectMessage: Text returned to the browser when it redirects the user to the given path.
    /// - Returns: Either the query parameterrs of the redirect URL, or an error if the HTTP server fails to start.
    func listen(port: UInt16, path: String, redirectMessage: String) -> Swift.Result<[String: String]?, HTTPRedirectListenerError>
}

public enum HTTPRedirectListenerError: FatalError {
    case httpServer(Error)

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .httpServer: return .abort
        }
    }

    /// Error description.
    public var description: String {
        switch self {
        case let .httpServer(error):
            return "The redirect HTTP server faild to start with the following error: \(error)."
        }
    }
}

private var runningServer: HttpServerIO!

public final class HTTPRedirectListener: HTTPRedirectListening {
    /// Default initializer.
    public init() {}

    // MARK: - HTTPRedirectListening

    public func listen(port: UInt16, path: String, redirectMessage: String) -> Swift.Result<[String: String]?, HTTPRedirectListenerError> {
        precondition(runningServer == nil, "Trying to start a redirect server for localhost:\(port)\(path) when there's already one running.")
        let httpServer = HttpServer()
        var result: Swift.Result<[String: String]?, HTTPRedirectListenerError> = .success(nil)

        httpServer[path] = { request in
            result = .success(request.queryParams.reduce(into: [String: String]()) { $0[$1.0] = $1.1 })
            DispatchQueue.global().async { httpServer.stop() }
            return HttpResponse.ok(.text(redirectMessage))
        }

        // If the user sends an interruption signal by pressing CTRL+C, we stop the server.
        Signals.trap(signals: [.int, .abrt]) { _ in runningServer!.stop() }

        do {
            runningServer = httpServer
            logger.pretty("Press \(.keystroke("CTRL + C")) once to cancel the process.")
            try httpServer.start(port)
        } catch {
            result = .failure(.httpServer(error))
        }

        runningServer = nil
        return result
    }
}
