import Combine
import Foundation

struct AtlasConnection: Decodable, Identifiable {
    let provider: String
    let name: String
    let configured: Bool
    let accountName: String?
    let status: String
    var id: String { provider }
    var connected: Bool { status != "not_connected" }
    var summary: String {
        if status == "needs_authorization" { return "Reconnect required" }
        if status == "connected" { return accountName ?? "Connected" }
        return configured ? "Not connected" : "Not enabled on this server"
    }
}

@MainActor
final class AtlasConnections: ObservableObject {
    typealias Request = ([String: Any]) async throws -> Data
    @Published private(set) var connections: [AtlasConnection] = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let request: Request
    private let authorize: (URL) async throws -> URL?
    private var generation = 0
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(request: @escaping Request, authorize: @escaping (URL) async throws -> URL?) {
        self.request = request
        self.authorize = authorize
    }

    func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await reload(); message = nil } catch { show(error) }
    }

    func connect(_ provider: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        let current = generation
        defer { busy = false }
        do {
            let data = try await request(["action": "begin", "provider": provider])
            guard current == generation else { return }
            let login = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let address = login?["authorization_url"] as? String, let url = URL(string: address),
                  let pending = login?["pending"] else { throw invalidResponse() }
            guard let callback = try await authorize(url) else { message = "Connection cancelled."; return }
            guard current == generation else { return }
            let result = try await request(["action": "complete", "pending": pending, "callback": callback.absoluteString])
            let response = try JSONSerialization.jsonObject(with: result) as? [String: Any]
            try await reload()
            guard current == generation else { return }
            if response?["status"] as? String != "connected" ||
                connections.first(where: { $0.provider == provider })?.status != "connected" {
                message = "The account was not connected. Try again."
            }
        } catch { if current == generation { show(error) } }
    }

    func disconnect(_ provider: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            _ = try await request(["action": "disconnect", "provider": provider])
            try await reload()
        } catch { show(error) }
    }

    func invalidate() {
        generation += 1
        connections = []
        message = nil
    }

    private func reload() async throws {
        struct Response: Decodable { let connections: [AtlasConnection] }
        let current = generation
        let data = try await request(["action": "list"])
        guard current == generation else { throw CancellationError() }
        connections = try decoder.decode(Response.self, from: data).connections
    }

    private func show(_ error: Error) {
        if !(error is CancellationError) { message = error.localizedDescription }
    }

    private func invalidResponse() -> Error {
        AtlasAuthenticationError(kind: "invalid_response", message: "Atlas returned an invalid connection response.")
    }
}
