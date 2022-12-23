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
            <div
              class="w-40 h-40 mb-10"
            >
              <svg viewBox="0 0 160 160" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="80" cy="80" r="80" fill="url(#paint0_linear)"></circle><path d="M39.6667 115.61C39.6667 115.61 56.5 129 80.5 129C104.5 129 121.333 115.61 121.333 115.61M35 92.878C35 92.878 64.1667 128 80.5 128M80.5 128C96.8333 128 126 92.878 126 92.878M80.5 128C64.1667 128 35 64.7805 35 64.7805M80.5 128C96.8333 128 126 64.7805 126 64.7805M80.5 128C72.0001 128 53.6667 40.1951 53.6667 40.1951M80.5 128C88.9999 128 107.333 40.1951 107.333 40.1951M80.8333 128L80.8333 32" stroke="white" stroke-width="4"></path><defs><linearGradient id="paint0_linear" x1="80" y1="0" x2="80" y2="160" gradientUnits="userSpaceOnUse"><stop stop-color="#6236FF"></stop><stop offset="1" stop-color="#3000DA"></stop></linearGradient></defs>
              </svg>
            </div>
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
