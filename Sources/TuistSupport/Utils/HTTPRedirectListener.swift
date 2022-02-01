import Foundation
import Swifter
import TSCBasic

public protocol HTTPRedirectListening: Any {
    /// Starts an HTTP server at the given port and blocks the process until a request is sent to the given path.
    /// - Parameters:
    ///   - port: Port for the HTTP server.
    ///   - path: Path we are expecting the browser to redirect the user to.
    ///   - redirectMessage: Text returned to the browser when it redirects the user to the given path.
    ///   - logoURL: The logo to show in the redirect page.
    /// - Returns: Either the query parameterrs of the redirect URL, or an error if the HTTP server fails to start.
    func listen(port: UInt16, path: String, redirectMessage: String, logoURL: URL) -> Swift
        .Result<[String: String]?, HTTPRedirectListenerError>
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

private var runningSemaphore: DispatchSemaphore!

public final class HTTPRedirectListener: HTTPRedirectListening {
    private let signalHandler: SignalHandling

    /// Default initializer.
    public init(signalHandler: SignalHandling = SignalHandler()) {
        self.signalHandler = signalHandler
    }

    // MARK: - HTTPRedirectListening

    public func listen(
        port: UInt16,
        path: String,
        redirectMessage: String,
        logoURL: URL
    ) -> Swift.Result<[String: String]?, HTTPRedirectListenerError> {
        precondition(
            runningSemaphore == nil,
            "Trying to start a redirect server for localhost:\(port)\(path) when there's already one running."
        )
        let httpServer = HttpServer()
        var result: Swift.Result<[String: String]?, HTTPRedirectListenerError> = .success(nil)

        runningSemaphore = DispatchSemaphore(value: 0)
        httpServer[path] = { request in
            result = .success(request.queryParams.reduce(into: [String: String]()) { $0[$1.0] = $1.1 })
            DispatchQueue.global().async { runningSemaphore.signal() }
            return HttpResponse.ok(.html(self.html(logoURL: logoURL, redirectMessage: redirectMessage)))
        }

        // Stop the server if the user sends an interruption signal by pressing CTRL+C
        signalHandler.trap { _ in runningSemaphore.signal() }

        do {
            logger.pretty("Press \(.keystroke("CTRL + C")) once to cancel the process.")
            try httpServer.start(port)
            runningSemaphore.wait()
        } catch {
            result = .failure(.httpServer(error))
        }

        runningSemaphore = nil
        return result
    }

    // swiftlint:disable:next function_body_length
    private func html(logoURL: URL, redirectMessage: String) -> String {
        """
        <!DOCTYPE html>

        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <link
              rel="icon"
              href="\(logoURL.absoluteString)"
            />
            <title>Redirecting</title>
            <meta name="description" content="Redirecting to Tuist" />
            <link
              href="https://unpkg.com/tailwindcss@^1.0/dist/tailwind.min.css"
              rel="stylesheet"
            />
          </head>

          <body
            class="flex h-screen w-screen flex-col justify-center items-center bg-gray-200"
          >
            <img
              class="w-40 h-40 mb-10"
              src="\(logoURL.absoluteString)"
            />
            <div class="bg-white shadow sm:rounded-lg">
              <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900">
                  Open your terminal 👩‍💻
                </h3>
                <div class="mt-2 max-w-xl text-sm leading-5 text-gray-500">
                  <p>
                    \(redirectMessage)
                  </p>
                </div>
                <!-- <div class="mt-3 text-sm leading-5">
                  <a
                    href="https://tuist.io/"
                    class="font-medium text-blue-600 hover:text-blue-500 transition ease-in-out duration-150"
                  >
                    Link &rarr;
                  </a> -->
                </div>
              </div>
            </div>
          </body>
        </html>
        """
    }
}
