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
    private var server: HttpServer?
    private var semaphore: DispatchSemaphore?
    
    public init() { }
    
    public func serve(path: AbsolutePath, port: UInt16) throws {
        // 1. Serves the directory (e.g. localhost:4040)
        // 2. Blocks the process until it gets a SIGKILL signal (ctrl + c)
                
        func okReponse(at path: String) throws -> HttpResponse {
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
                guard try filePath.exists() else {
                    return .notFound
                }
                if try filePath.directory() {
                    let indexPath = filePath + "/index.html"
                    return try okReponse(at: indexPath)
                } else {
                    return try okReponse(at: filePath)
                }
            } catch {
                return .internalServerError
            }
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
