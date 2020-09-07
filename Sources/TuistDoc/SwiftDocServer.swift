import Dispatch
import Foundation
import Signals
import Swifter
import TSCBasic
import TuistSupport

public protocol SwiftDocServing {
    var baseURL: String { get }
    func serve(path: AbsolutePath, port: UInt16) throws
}

public final class SwiftDocServer: SwiftDocServing {
    private static let index = "index.html"
    private static var temporaryDirectory: AbsolutePath?

    private let fileHandling: FileHandling
    private let opener: Opening
    private var server: HttpServer?
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

        server = HttpServer()

        server?["/:param"] = { [weak self] request in
            guard let self = self else { return .internalServerError }

            guard let (_, value) = request.params.first else {
                return .notFound
            }

            let filePath = path.appending(component: value)
            guard self.fileHandling.exists(filePath) else { return .notFound }

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
            print("Server start error: \(error)")
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
