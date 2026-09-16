#if os(macOS)
    import Foundation
    import Network
    import os
    import Synchronization

    /// A loopback HTTP/1.1 server that answers each request with the next scripted reply over a real
    /// socket, so a body can end partway through the way a dropped or stalled connection does.
    final class LocalArtifactServer: @unchecked Sendable {
        struct Request: Equatable {
            let range: String?
            let ifRange: String?
        }

        struct Reply {
            var status: Int
            var headers: [String: String]
            var body: Data
            var chunkSize = Int.max
            var chunkDelayMilliseconds = 0
            /// Keeps the connection open without sending anything once the body is out.
            var stallsAfterBody = false
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "dev.tuist.LocalArtifactServer")
        private let state = Mutex((replies: [Reply](), requests: [Request](), connections: [NWConnection]()))

        init(replies: [Reply]) async throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
            state.withLock { $0.replies = replies }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            let started = OSAllocatedUnfairLock(initialState: false)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                listener.stateUpdateHandler = { state in
                    let result: Result<Void, any Error>
                    switch state {
                    case .ready: result = .success(())
                    case let .failed(error): result = .failure(error)
                    default: return
                    }
                    let isFirst = started.withLock { started in
                        defer { started = true }
                        return !started
                    }
                    if isFirst { continuation.resume(with: result) }
                }
                listener.start(queue: queue)
            }
        }

        deinit {
            listener.cancel()
            state.withLock { $0.connections }.forEach { $0.cancel() }
        }

        var url: URL {
            URL(string: "http://127.0.0.1:\(listener.port!.rawValue)")!
        }

        var requests: [Request] {
            state.withLock { $0.requests }
        }

        private func accept(_ connection: NWConnection) {
            state.withLock { $0.connections.append(connection) }
            connection.start(queue: queue)
            readHead(of: connection, buffered: Data())
        }

        private func readHead(of connection: NWConnection, buffered: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self, error == nil else { return }
                let buffered = buffered + (data ?? Data())
                guard let end = buffered.range(of: Data("\r\n\r\n".utf8)) else {
                    if !isComplete { readHead(of: connection, buffered: buffered) }
                    return
                }
                respond(on: connection, head: String(decoding: buffered[..<end.lowerBound], as: UTF8.self))
            }
        }

        private func respond(on connection: NWConnection, head: String) {
            var fields: [String: String] = [:]
            for line in head.split(separator: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            var reply = state.withLock { state in
                state.requests.append(Request(range: fields["range"], ifRange: fields["if-range"]))
                return state.replies.removeFirst()
            }
            reply.body = Data(reply.body)
            var responseHead = "HTTP/1.1 \(reply.status) \(HTTPURLResponse.localizedString(forStatusCode: reply.status))\r\n"
            for (name, value) in reply.headers {
                responseHead += "\(name): \(value)\r\n"
            }
            responseHead += "Connection: close\r\n\r\n"
            connection.send(content: Data(responseHead.utf8), completion: .contentProcessed { _ in })
            send(reply, from: 0, on: connection)
        }

        private func send(_ reply: Reply, from offset: Int, on connection: NWConnection) {
            guard offset < reply.body.count else {
                if !reply.stallsAfterBody {
                    connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                }
                return
            }
            let end = offset + min(reply.chunkSize, reply.body.count - offset)
            let chunk = reply.body.subdata(in: offset ..< end)
            connection.send(content: chunk, completion: .contentProcessed { [weak self] _ in
                self?.queue.asyncAfter(deadline: .now() + .milliseconds(reply.chunkDelayMilliseconds)) {
                    self?.send(reply, from: end, on: connection)
                }
            })
        }
    }
#endif
