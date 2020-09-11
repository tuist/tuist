import Dispatch
import Foundation
import Signals
import Swifter
import TSCBasic
import TuistSupport

public protocol SwiftDocServing {
    /// Base url for the server
    var baseURL: String { get }

    /// Serves the documentation at a given path
    /// - Parameters:
    ///   - path: Path to the folder containing the documentation
    ///   - port: Port to use for hosting the website
    func serve(path: AbsolutePath, port: UInt16) throws
}

public final class SwiftDocServer: SwiftDocServing {
    private static let index = "index.html"
    private static var temporaryDirectory: AbsolutePath?

    /// Utility to manipulate files
    private let fileHandling: FileHandling

    /// Utility to open files
    private let opener: Opening

    /// HTTPServer from Swifter
    private var server: HttpServer?

    /// Semaphore to block the execution
    private var semaphore: DispatchSemaphore?

    public let baseURL: String = "http://localhost"

    public init(fileHandling: FileHandling = FileHandler(),
                opener: Opening = Opener())
    {
        self.fileHandling = fileHandling
        self.opener = opener
    }

    public func serve(path: AbsolutePath, port: UInt16) throws {
        SwiftDocServer.temporaryDirectory = path

        func okReponse(fileAt path: AbsolutePath) throws -> HttpResponse {
            guard let file = try? path.pathString.openForReading() else {
                return .notFound
            }
            return .raw(200, "OK", [:]) { writer in
                try? writer.write(file)
                file.close()
            }
        }

        func handleRequest(_ request: HttpRequest) -> HttpResponse {
            guard let (_, value) = request.params.first else {
                return .notFound
            }

            let filePath = path.appending(component: value)
            guard fileHandling.exists(filePath) else { return .notFound }

            do {
                if try filePath.pathString.directory() {
                    // this is how swift-doc generates it
                    let indexPath = filePath
                        .appending(component: SwiftDocServer.index)
                    return try okReponse(fileAt: indexPath)
                } else {
                    return try okReponse(fileAt: filePath)
                }
            } catch {
                return .internalServerError
            }
        }

        server = HttpServer()

        server?["/:param"] = handleRequest

        Signals.trap(signals: [.int, .abrt]) { _ in
            // swiftlint:disable:next force_try
            logger.pretty("Deleting temporary folder.")
            try! SwiftDocServer.temporaryDirectory.map(FileHandler.shared.delete)
            exit(0)
        }

        guard let serverURL = URL(string: baseURL + ":\(port)") else { throw Error.unableToStartServer(at: port) }

        semaphore = DispatchSemaphore(value: 0)
        do {
            logger.pretty("Starting server at \(.bold(.raw(serverURL.absoluteString))).")
            try server?.start(port, forceIPv4: true)

            let urlPath = serverURL.appendingPathComponent(SwiftDocServer.index)
            logger.pretty("Opening the documentation. Press \(.keystroke("CTRL + C")) once you are done.")
            try opener.open(url: urlPath)

            semaphore?.wait()
        } catch {
            logger.error("Server start error: \(error)")
            semaphore?.signal()
            throw Error.unableToStartServer(at: port)
        }
    }
}

// MARK: - Error

extension SwiftDocServer {
    enum Error: FatalError {
        case unableToStartServer(at: UInt16)

        var description: String {
            switch self {
            case let .unableToStartServer(port):
                return "We were unable to start the server at port \(port)."
            }
        }

        var type: ErrorType {
            switch self {
            case .unableToStartServer:
                return .abort
            }
        }
    }
}
