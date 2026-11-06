import Foundation
import TuistHTTP
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct ThreadPage: Decodable {
    public let threads: [DemoThread]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case threads
        case nextCursor = "next_cursor"
    }
}

public struct ThreadRepository: Decodable, Identifiable, Hashable {
    public var id: String { fullName }
    public let fullName: String
    public let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
    }
}

public struct ThreadShipPreview: Decodable, Identifiable {
    public var id: UUID { requestID }
    public let headSHA: String
    public let baseSHA: String
    public let diff: String
    public let targetBranch: String
    public let mode: String
    public let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case diff, mode
        case headSHA = "head_sha"
        case baseSHA = "base_sha"
        case targetBranch = "target_branch"
        case requestID = "request_id"
    }
}

public struct ThreadClientError: LocalizedError, HTTPStatusCodeError {
    public let httpStatusCode: Int
    public var errorDescription: String? {
        "The thread request could not be completed (HTTP \(httpStatusCode))."
    }
}

/// Account-scoped authenticated transport. Credentials never leave the shared service layer.
public struct ThreadClient {
    private static let liveSession = URLSession.tuistDiscovery
    public let account: String
    private let serverURL: URL
    private let session: URLSession
    private let token: () async throws -> String
    private let perform: (URLRequest) async throws -> (Data, URLResponse)

    public init(account: String, serverURL: URL) {
        let session = Self.liveSession
        self.init(account: account, serverURL: serverURL, session: session, token: {
            guard let token = try await ServerAuthenticationController().authenticationToken(serverURL: serverURL) else {
                throw ThreadClientError(httpStatusCode: 401)
            }
            return token.value
        }, perform: { try await session.data(for: $0) })
    }

    init(
        account: String, serverURL: URL, session: URLSession,
        token: @escaping () async throws -> String,
        perform: @escaping (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.account = account
        self.serverURL = serverURL
        self.session = session
        self.token = token
        self.perform = perform
    }

    public func threads(cursor: String? = nil) async throws -> ThreadPage {
        try await request(query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
    }

    public func thread(id: String, before: Int? = nil) async throws -> DemoThread {
        try await request(path: [id], query: before.map { [URLQueryItem(name: "before", value: String($0))] } ?? [])
    }

    public func repositories() async throws -> [ThreadRepository] {
        struct Response: Decodable { let repositories: [ThreadRepository] }
        let response: Response = try await request(path: ["repositories"])
        return response.repositories
    }

    public func models() async throws -> ThreadModelCatalog {
        try await request(path: ["models"])
    }

    public func create(
        content: String, repository: ThreadRepository?, provider: String, model: String, requestID: UUID
    ) async throws -> DemoThread {
        var body: [String: Any] = [
            "content": content, "request_id": requestID.uuidString.lowercased(), "provider": provider, "model": model,
        ]
        body["repository"] = repository.map { $0.fullName as Any } ?? NSNull()
        if let repository { body["base_branch"] = repository.defaultBranch }
        return try await request(method: "POST", body: body)
    }

    public func send(_ content: String, threadID: String, requestID: UUID) async throws -> DemoThread {
        try await request(path: [threadID, "messages"], method: "POST", body: [
            "content": content, "request_id": requestID.uuidString.lowercased(),
        ])
    }

    public func archive(id: String, archived: Bool) async throws -> DemoThread {
        try await request(path: [id], method: "PATCH", body: ["status": archived ? "archived" : "active"])
    }

    public func shipPreview(id: String) async throws -> ThreadShipPreview {
        try await request(path: [id, "ship-preview"], method: "POST", body: [:])
    }

    /// Only called from explicit approval of this exact reviewed snapshot, never from a suggestion or tool.
    public func ship(id: String, approval: ThreadShipPreview) async throws -> DemoThread {
        try await request(path: [id, "ship"], method: "POST", body: [
            "request_id": approval.requestID.uuidString.lowercased(),
            "head_sha": approval.headSHA, "base_sha": approval.baseSHA,
        ])
    }

    private func request<Response: Decodable>(
        path: [String] = [], method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil
    ) async throws -> Response {
        var url = serverURL
        for component in ["api", "accounts", account, "threads"] + path {
            url.appendPathComponent(component)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let execute = {
            let (data, response) = try await perform(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(status) else { throw ThreadClientError(httpStatusCode: status) }
            return data
        }
        // Writes are deliberately not replayed automatically until server deduplication is qualified.
        let data: Data
        if method == "GET" { data = try await HTTPRetryPolicy().run(execute) } else { data = try await execute() }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// A socket is scoped to the caller's foreground task. Every reconnect rejoins and invalidates history.
    public func watch(
        threadID: String? = nil,
        invalidate: @escaping () async -> Void,
        disconnected: @escaping () async -> Void
    ) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await connection(threadID: threadID, invalidate: invalidate)
            } catch {
                guard !Task.isCancelled else { return }
                await disconnected()
                attempt = min(attempt + 1, 5)
                do { try await Task.sleep(for: .seconds(1 << attempt)) } catch { return }
            }
        }
    }

    private func connection(threadID: String?, invalidate: @escaping () async -> Void) async throws {
        let request = socketRequest(token: try await token())
        let socket = session.webSocketTask(with: request)
        let liveness = ThreadSocketLiveness()
        let topic = "threads:\(account):\(threadID ?? "inbox")"
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
            try await socket.send(.string(Self.frame(join: "1", ref: "1", topic: topic, event: "phx_join")))
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    while !Task.isCancelled {
                        guard await !liveness.waiting else { throw URLError(.timedOut) }
                        let ref = UUID().uuidString
                        await liveness.expect(ref)
                        try await socket.send(.string(Self.frame(join: nil, ref: ref, topic: "phoenix", event: "heartbeat")))
                        try await Task.sleep(for: .seconds(20))
                    }
                }
                group.addTask {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case let .string(value): data = Data(value.utf8)
                        case let .data(value): data = value
                        @unknown default: continue
                        }
                        guard let frame = try JSONSerialization.jsonObject(with: data) as? [Any], frame.count == 5,
                              let event = frame[3] as? String else { continue }
                        if event == "phx_error" || event == "phx_close" { throw URLError(.networkConnectionLost) }
                        if event == "phx_reply", let ref = frame[1] as? String {
                            await liveness.acknowledge(ref)
                        }
                        guard frame[2] as? String == topic else { continue }
                        if event == "phx_reply", let payload = frame[4] as? [String: Any] {
                            guard payload["status"] as? String == "ok" else { throw ThreadClientError(httpStatusCode: 403) }
                            await invalidate()
                        } else if event == "snapshot" {
                            await invalidate()
                        }
                    }
                }
                defer { group.cancelAll(); socket.cancel(with: .goingAway, reason: nil) }
                try await group.next()
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    func socketRequest(token: String) -> URLRequest {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("threads/socket/websocket"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "vsn", value: "2.0.0")]
        let encoded = Data(token.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var request = URLRequest(url: components.url!)
        request.setValue("phoenix, base64url.bearer.phx.\(encoded)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        return request
    }

    static func frame(join: String?, ref: String, topic: String, event: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [join as Any? ?? NSNull(), ref, topic, event, [:]] as [Any])
        guard let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return value
    }
}

private actor ThreadSocketLiveness {
    private var pending: String? = "1"
    var waiting: Bool { pending != nil }
    func expect(_ ref: String) { pending = ref }
    func acknowledge(_ ref: String) { if pending == ref { pending = nil } }
}
