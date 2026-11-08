import Foundation
import TuistHTTP
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct JamPage: Decodable {
    public let jams: [DemoJam]
    public let nextCursor: String?

    public init(jams: [DemoJam], nextCursor: String?) {
        self.jams = jams
        self.nextCursor = nextCursor
    }

    public func mergingRefresh(_ page: JamPage) -> JamPage {
        guard let boundary = page.jams.last,
              boundary.revision != nil,
              let index = jams.firstIndex(where: { $0.id == boundary.id }),
              jams[index] == boundary
        else { return page }
        let incoming = Set(page.jams.map(\.id))
        // A moved overlap alone does not prove that the two recency windows meet.
        guard jams[...index].allSatisfy({ incoming.contains($0.id) }) else { return page }
        return JamPage(
            jams: page.jams + jams.filter { !incoming.contains($0.id) },
            nextCursor: nextCursor
        )
    }

    enum CodingKeys: String, CodingKey {
        case jams
        case threads
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jams = try container.decode([DemoJam].self, forKey: container.contains(.jams) ? .jams : .threads)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

public struct JamRepository: Decodable, Identifiable, Hashable {
    public var id: String { fullName }
    public let fullName: String
    public let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
    }
}

public struct JamShipPreview: Decodable, Identifiable {
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

public struct JamClientError: LocalizedError, HTTPStatusCodeError {
    public let httpStatusCode: Int
    public var errorDescription: String? {
        "The jam request could not be completed (HTTP \(httpStatusCode))."
    }
}

/// Account-scoped authenticated transport. Credentials never leave the shared service layer.
public struct JamClient {
    private static let liveSession = URLSession.tuistDiscovery
    public let account: String
    private let serverURL: URL
    private let session: URLSession
    private let token: () async throws -> String
    private let perform: (URLRequest) async throws -> (Data, URLResponse)

    public init(account: String, serverURL: URL) {
        let session = Self.liveSession
        let authentication = ServerAuthenticationController()
        self.init(account: account, serverURL: serverURL, session: session, token: {
            guard let token = try await authentication.authenticationToken(serverURL: serverURL) else {
                throw JamClientError(httpStatusCode: 401)
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

    public func jams(cursor: String? = nil) async throws -> JamPage {
        try await request(query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
    }

    public func jam(id: String, before: Int? = nil) async throws -> DemoJam {
        try await request(path: [id], query: before.map { [URLQueryItem(name: "before", value: String($0))] } ?? [])
    }

    public func repositories() async throws -> [JamRepository] {
        struct Response: Decodable { let repositories: [JamRepository] }
        let response: Response = try await request(path: ["repositories"])
        return response.repositories
    }

    public func models() async throws -> JamModelCatalog {
        try await request(path: ["models"])
    }

    public func create(
        content: String, repository: JamRepository?, provider: String, model: String, requestID: UUID
    ) async throws -> DemoJam {
        var body: [String: Any] = [
            "content": content, "request_id": requestID.uuidString.lowercased(), "provider": provider, "model": model,
        ]
        body["repository"] = repository.map { $0.fullName as Any } ?? NSNull()
        if let repository { body["base_branch"] = repository.defaultBranch }
        return try await request(method: "POST", body: body)
    }

    public func send(_ content: String, jamID: String, requestID: UUID) async throws -> DemoJam {
        try await request(path: [jamID, "messages"], method: "POST", body: [
            "content": content, "request_id": requestID.uuidString.lowercased(),
        ])
    }

    public func archive(id: String, archived: Bool) async throws -> DemoJam {
        try await request(path: [id], method: "PATCH", body: ["status": archived ? "archived" : "active"])
    }

    public func shipPreview(id: String) async throws -> JamShipPreview {
        try await request(path: [id, "ship-preview"], method: "POST", body: [:])
    }

    /// Only called from explicit approval of this exact reviewed snapshot, never from a suggestion or tool.
    public func ship(id: String, approval: JamShipPreview) async throws -> DemoJam {
        try await request(path: [id, "ship"], method: "POST", body: [
            "request_id": approval.requestID.uuidString.lowercased(),
            "head_sha": approval.headSHA, "base_sha": approval.baseSHA,
            "target_branch": approval.targetBranch, "mode": approval.mode,
        ])
    }

    private func request<Response: Decodable>(
        path: [String] = [], method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil
    ) async throws -> Response {
        if method == "GET" {
            do {
                return try await request(dialect: .jams, path: path, query: query)
            } catch let error as JamClientError where error.httpStatusCode == 404 {
                return try await request(dialect: .legacy, path: path, query: query)
            }
        }
        // Negotiate with a safe read, never by replaying a potentially completed write.
        let dialect = try await negotiatedDialect()
        return try await request(dialect: dialect, path: path, method: method, query: query, body: body)
    }

    enum Dialect: String {
        case jams
        case legacy = "threads"
    }

    private func negotiatedDialect() async throws -> Dialect {
        do {
            let _: JamModelCatalog = try await request(dialect: .jams, path: ["models"])
            return .jams
        } catch let error as JamClientError where error.httpStatusCode == 404 {
            let _: JamModelCatalog = try await request(dialect: .legacy, path: ["models"])
            return .legacy
        }
    }

    private func request<Response: Decodable>(
        dialect: Dialect, path: [String] = [], method: String = "GET",
        query: [URLQueryItem] = [], body: [String: Any]? = nil
    ) async throws -> Response {
        var url = serverURL
        for component in ["api", "accounts", account, dialect.rawValue] + path {
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
            guard (200 ..< 300).contains(status) else { throw JamClientError(httpStatusCode: status) }
            return data
        }
        // Writes are deliberately not replayed automatically until server deduplication is qualified.
        let data: Data
        if method == "GET" { data = try await HTTPRetryPolicy().run(execute) } else { data = try await execute() }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// A socket is scoped to the caller's foreground task. Every reconnect rejoins and invalidates history.
    public func watch(
        jamID: String? = nil,
        invalidate: @escaping () async -> Void,
        disconnected: @escaping () async -> Void
    ) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try await connection(jamID: jamID, invalidate: invalidate)
            } catch {
                guard !Task.isCancelled else { return }
                await disconnected()
                attempt = min(attempt + 1, 5)
                do { try await Task.sleep(for: .seconds(1 << attempt)) } catch { return }
            }
        }
    }

    private func connection(jamID: String?, invalidate: @escaping () async -> Void) async throws {
        let (request, topic) = try await socketConfiguration(jamID: jamID)
        let socket = session.webSocketTask(with: request)
        let liveness = JamSocketLiveness()
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
                            guard payload["status"] as? String == "ok" else { throw JamClientError(httpStatusCode: 403) }
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

    func socketConfiguration(jamID: String?) async throws -> (URLRequest, String) {
        let dialect = try await negotiatedDialect()
        return (
            socketRequest(token: try await token(), dialect: dialect),
            "\(dialect.rawValue):\(account):\(jamID ?? "inbox")"
        )
    }

    func socketRequest(token: String, dialect: Dialect = .jams) -> URLRequest {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("\(dialect.rawValue)/socket/websocket"),
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

private actor JamSocketLiveness {
    private var pending: String? = "1"
    var waiting: Bool { pending != nil }
    func expect(_ ref: String) { pending = ref }
    func acknowledge(_ ref: String) { if pending == ref { pending = nil } }
}
