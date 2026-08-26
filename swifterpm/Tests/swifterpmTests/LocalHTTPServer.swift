import Foundation
import Synchronization

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// A loopback HTTP/1.1 server that replays a scripted sequence of responses, so tests can
/// drive redirect, retry and status-code handling without a network.
final class LocalHTTPServer: Sendable {
    struct Response: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: String

        init(statusCode: Int, headers: [String: String] = [:], body: String = "") {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }

        static func ok(_ body: String) -> Response {
            Response(statusCode: 200, body: body)
        }

        static func status(_ statusCode: Int, headers: [String: String] = [:]) -> Response {
            Response(statusCode: statusCode, headers: headers)
        }

        static func redirect(to location: String) -> Response {
            Response(statusCode: 303, headers: ["Location": location])
        }
    }

    private struct State {
        var routes: [String: [Response]] = [:]
        var recordedPaths: [String] = []
        var stopped = false
    }

    private let state = Mutex(State())
    private let listeningSocket: Int32

    let port: UInt16

    enum Failure: Error {
        case socketUnavailable
        case bindFailed
    }

    init() throws {
        #if canImport(Glibc)
            let streamType = Int32(SOCK_STREAM.rawValue)
        #else
            let streamType = SOCK_STREAM
        #endif

        let descriptor = socket(AF_INET, streamType, 0)
        guard descriptor >= 0 else { throw Failure.socketUnavailable }

        var reuse: Int32 = 1
        setsockopt(
            descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw Failure.bindFailed
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else {
            close(descriptor)
            throw Failure.bindFailed
        }

        listeningSocket = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    /// Queues the responses served for `path`, in order. The last one repeats once exhausted.
    func respond(to path: String, with responses: [Response]) {
        state.withLock { $0.routes[path] = responses }
    }

    func url(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    /// Paths of every request served so far, in order, so tests can assert retry counts.
    var requestedPaths: [String] {
        state.withLock { $0.recordedPaths }
    }

    func start() {
        let thread = Thread { [self] in acceptLoop() }
        thread.stackSize = 512 * 1024
        thread.start()
    }

    func stop() {
        let alreadyStopped = state.withLock { state -> Bool in
            let wasStopped = state.stopped
            state.stopped = true
            return wasStopped
        }
        guard !alreadyStopped else { return }
        shutdown(listeningSocket, Int32(SHUT_RDWR))
        close(listeningSocket)
    }

    private func acceptLoop() {
        while !state.withLock({ $0.stopped }) {
            let connection = accept(listeningSocket, nil, nil)
            guard connection >= 0 else { return }
            serve(connection: connection)
            close(connection)
        }
    }

    private func serve(connection: Int32) {
        guard let path = readRequestPath(connection: connection) else { return }

        let response = state.withLock { state -> Response in
            state.recordedPaths.append(path)
            guard var queued = state.routes[path], !queued.isEmpty else {
                return Response(statusCode: 404)
            }
            let next = queued.removeFirst()
            state.routes[path] = queued.isEmpty ? [next] : queued
            return next
        }

        write(response: response, to: connection)
    }

    /// Routes are keyed on the path alone, so a redirect target carrying a query string
    /// still matches the route registered for its path.
    private func readRequestPath(connection: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = recv(connection, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }

        let request = String(bytes: buffer[0 ..< received], encoding: .utf8) ?? ""
        let requestLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let components = requestLine.split(separator: " ")
        guard components.count >= 2 else { return nil }
        return String(components[1].split(separator: "?", maxSplits: 1)[0])
    }

    private func write(response: Response, to connection: Int32) {
        let body = Array(response.body.utf8)
        var head = "HTTP/1.1 \(response.statusCode) \(Self.reason(for: response.statusCode))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (name, value) in response.headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var payload = Array(head.utf8)
        payload.append(contentsOf: body)
        payload.withUnsafeBufferPointer { buffer in
            var sent = 0
            while sent < buffer.count {
                let written = send(connection, buffer.baseAddress! + sent, buffer.count - sent, 0)
                guard written > 0 else { return }
                sent += written
            }
        }
    }

    private static func reason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 303: return "See Other"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 429: return "Too Many Requests"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}

func withLocalHTTPServer<T>(_ body: (LocalHTTPServer) async throws -> T) async throws -> T {
    let server = try LocalHTTPServer()
    server.start()
    do {
        let result = try await body(server)
        server.stop()
        return result
    } catch {
        server.stop()
        throw error
    }
}
