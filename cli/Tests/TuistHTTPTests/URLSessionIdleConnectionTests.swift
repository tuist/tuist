#if os(macOS)
    import Foundation
    import Network
    import Testing
    import TuistEnvironmentTesting

    @testable import TuistHTTP

    struct URLSessionIdleConnectionTests {
        @Test(.withMockedEnvironment())
        func configuration_closes_idle_connections_before_the_server_does() {
            let configuration = tuistURLSessionConfiguration()

            #expect(idleConnectionTimeout(of: configuration) == 10)
        }

        @Test(.withMockedEnvironment(), .timeLimit(.minutes(1)))
        func session_opens_a_new_connection_after_the_idle_timeout() async throws {
            let server = try ConnectionCountingHTTPServer()
            defer { server.stop() }
            let port = try await server.start()
            let session = URLSession.tuistShared(useEnvironmentProxy: false)
            defer { session.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            _ = try await session.data(from: url)
            try await Task.sleep(for: .seconds(tuistIdleConnectionTimeout + 1.5))
            _ = try await session.data(from: url)

            #expect(server.connections == 2)
        }
    }

    private final class ConnectionCountingHTTPServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "dev.tuist.ConnectionCountingHTTPServer")
        private let lock = NSLock()
        private var count = 0
        private var accepted: [NWConnection] = []

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
        }

        var connections: Int {
            lock.withLock { count }
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                lock.withLock {
                    self.count += 1
                    self.accepted.append(connection)
                }
                connection.start(queue: queue)
                serve(connection, buffer: Data())
            }
            return try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
            lock.withLock { accepted }.forEach { $0.cancel() }
        }

        private func serve(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                let terminator = Data("\r\n\r\n".utf8)
                while let range = buffer.range(of: terminator) {
                    buffer.removeSubrange(buffer.startIndex ..< range.upperBound)
                    let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                serve(connection, buffer: buffer)
            }
        }
    }
#endif
