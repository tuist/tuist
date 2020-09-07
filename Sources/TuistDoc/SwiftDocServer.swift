import Swifter
import Dispatch
import TSCBasic
import Signals
import TuistSupport

import Foundation

public protocol SwiftDocServing {
    func serve(path: AbsolutePath, port: UInt16) throws
}

public final class SwiftDocServer: SwiftDocServing {
    private static var temporaryDirectory: AbsolutePath?

    private var server: HttpServer?
    private var semaphore: DispatchSemaphore?
        
    public init() { }
    
    public func serve(path: AbsolutePath, port: UInt16) throws {
        SwiftDocServer.temporaryDirectory = path

        // 1. Serves the directory (e.g. localhost:4040)
        // 2. Blocks the process until it gets a SIGKILL signal (ctrl + c)
                
        func okReponse(fileAt path: String) throws -> HttpResponse {
            guard let file = try? path.openForReading() else {
                return .notFound
            }
            return .raw(200, "OK", [:], { writer in
                try? writer.write(file)
                file.close()
            })
        }
        
        server = HttpServer()

        server?["/:param"] = { request in
            guard let (_, value) = request.params.first else {
                return .notFound // we could default to an error screen
            }
            let filePath = path.pathString + String.pathSeparator + value
            do {
                guard try filePath.exists() else { return .notFound }
                
                if try filePath.directory() {
                    let indexPath = filePath + "/index.html"
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
            try! SwiftDocServer.temporaryDirectory.map(FileHandler.shared.delete)
            exit(0)
        }

        semaphore = DispatchSemaphore(value: 0)
        do {
            try server?.start(9080, forceIPv4: true)
            let urlPath = "http://localhost:9080/index.html"
            try System.shared.run(["open", urlPath])
            
            print("Server has started ( port = \(try server?.port()) ). Try to connect now...")
            semaphore?.wait()
        } catch {
            print("Server start error: \(error)")
            semaphore?.signal()
        }
    }
}
