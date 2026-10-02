import Foundation
import Synchronization
@testable import SwifterPMCore

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

/// A loopback HTTP/1.1 server that publishes a git repository over git's dumb HTTP transport
/// and answers any request carrying an `Authorization` header with a 401, the way github.com
/// rejects a credential it does not accept instead of serving a public repository anonymously.
final class LocalGitHTTPServer: Sendable {
    private struct State {
        var authenticatedRequests: [String] = []
        var anonymousRequests: [String] = []
        var stopped = false
    }

    private let root: URL
    private let state = Mutex(State())
    private let listeningSocket: Int32

    let port: UInt16

    enum Failure: Error {
        case socketUnavailable
        case bindFailed
    }

    init(root: URL) throws {
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

        self.root = root
        listeningSocket = descriptor
        port = UInt16(bigEndian: boundAddress.sin_port)
    }

    /// The base git matches `http.<base>.*` configuration against.
    var baseURL: String { "http://127.0.0.1:\(port)/" }

    func url(path: String) -> String { "http://127.0.0.1:\(port)\(path)" }

    var authenticatedRequests: [String] { state.withLock { $0.authenticatedRequests } }

    var anonymousRequests: [String] { state.withLock { $0.anonymousRequests } }

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
        guard let head = readRequestHead(connection: connection) else { return }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return }
        let path = String(requestLine[1].split(separator: "?", maxSplits: 1)[0])
        let isAuthenticated = lines.dropFirst().contains {
            $0.lowercased().hasPrefix("authorization:")
        }

        state.withLock { state in
            if isAuthenticated {
                state.authenticatedRequests.append(path)
            } else {
                state.anonymousRequests.append(path)
            }
        }

        guard !isAuthenticated else {
            write(
                statusCode: 401,
                headers: ["WWW-Authenticate": #"Basic realm="git""#],
                body: Data(),
                to: connection
            )
            return
        }
        guard let contents = contents(at: path) else {
            write(statusCode: 404, headers: [:], body: Data(), to: connection)
            return
        }
        write(
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"],
            body: contents,
            to: connection
        )
    }

    private func readRequestHead(connection: Int32) -> String? {
        var accumulated: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while accumulated.count < 64 * 1024 {
            let received = recv(connection, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            accumulated.append(contentsOf: buffer[0 ..< received])
            if let head = String(bytes: accumulated, encoding: .utf8), head.contains("\r\n\r\n") {
                return head
            }
        }
        return String(bytes: accumulated, encoding: .utf8)
    }

    private func contents(at path: String) -> Data? {
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains("..") else { return nil }
        let url = components.reduce(root) { $0.appendingPathComponent($1) }
        return try? Data(contentsOf: url)
    }

    private func write(statusCode: Int, headers: [String: String], body: Data, to connection: Int32) {
        var head = "HTTP/1.1 \(statusCode) \(Self.reason(for: statusCode))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (name, value) in headers {
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
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Status"
        }
    }
}

/// Publishes `repository` as a git dumb HTTP repository underneath `root`, and returns the
/// server that serves it anonymously while rejecting every authenticated request.
func withLocalGitHTTPServer<T>(
    root: URL,
    repository: String,
    tag: String,
    _ body: (LocalGitHTTPServer) async throws -> T
) async throws -> T {
    let work = root.appendingPathComponent("work")
    try await fileSystem.makeDirectory(
        at: work.absolutePath, options: [.createTargetParentDirectories]
    )
    try await fileSystem.atomicWrite("public\n", to: work.appendingPathComponent("README.md"))
    try await SystemProcess.run("/usr/bin/git", ["init", "-q"], workingDirectory: work)
    try await SystemProcess.run("/usr/bin/git", ["add", "."], workingDirectory: work)
    try await SystemProcess.run(
        "/usr/bin/git",
        [
            "-c", "user.name=Repro",
            "-c", "user.email=repro@example.com",
            "commit", "-q", "-m", "initial",
        ],
        workingDirectory: work
    )
    try await SystemProcess.run("/usr/bin/git", ["tag", tag], workingDirectory: work)
    // Git's dumb HTTP transport reads the static `info/refs` this writes, so the repository
    // can be served as plain files instead of needing a git-aware backend.
    try await SystemProcess.run("/usr/bin/git", ["update-server-info"], workingDirectory: work)
    try await fileSystem.move(
        from: work.appendingPathComponent(".git").absolutePath,
        to: root.appendingPathComponent(repository).absolutePath,
        options: []
    )
    try await fileSystem.remove(work.absolutePath)

    let server = try LocalGitHTTPServer(root: root)
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
