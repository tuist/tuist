import Foundation
import SwiftUI

struct AtlasPerson: Decodable, Identifiable {
    let id: String
    let name: String
    let email: String
    let online: Bool
    let here: Bool
}

@MainActor
final class AtlasPresence: ObservableObject {
    private struct Opened: Decodable { let connection: String }
    private struct Snapshot: Decodable {
        let sequence: UInt64
        let people: [AtlasPerson]
        let selfId: String?
        let location: [String: String]?
        let error: String?
        let needsSession: Bool?
    }

    @Published private(set) var people: [AtlasPerson] = []
    @Published private(set) var selfId: String?
    @Published private(set) var errorMessage: String?
    private let request: ([String: Any]) async throws -> Data
    private var connection: String?
    private var location: [String: String] = [:]
    private var active = false
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var updating = false

    init(request: @escaping ([String: Any]) async throws -> Data) { self.request = request }

    func show(resource: String? = nil, id: String? = nil) {
        var next: [String: String] = [:]
        if let resource { next["resource"] = resource }
        if let id { next["id"] = id }
        guard location != next else { return }
        location = next
        people = []
        updateLocation()
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        generation += 1
        if value { start() } else {
            selfId = nil
            people = []
            if let connection { Task { _ = try? await request(["action": "close", "connection": connection]) } }
        }
    }

    func stop() async {
        setActive(false)
        await worker?.value
    }

    private func start() {
        guard active, worker == nil else { return }
        let started = generation
        worker = Task {
            var refreshSession = false
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let opened = try decoder.decode(Opened.self, from: await request(["action": "open"]))
                connection = opened.connection
                updateLocation()
                var sequence: UInt64 = 0
                while active, generation == started {
                    let snapshot = try decoder.decode(Snapshot.self, from: await request([
                        "action": "next", "connection": opened.connection, "after": sequence
                    ]))
                    guard active, generation == started else { break }
                    sequence = snapshot.sequence
                    if snapshot.needsSession == true { selfId = nil; refreshSession = true; break }
                    if let error = snapshot.error {
                        selfId = nil
                        people = []
                        errorMessage = error == "sign_in_required" ? "Sign in to Atlas again." : "Reconnecting to Atlas…"
                    } else if snapshot.location == location {
                        selfId = snapshot.selfId
                        people = snapshot.people
                        errorMessage = nil
                    }
                }
            } catch {
                if active, generation == started { errorMessage = "Presence is unavailable. Reopen Atlas to retry." }
            }
            if let connection { _ = try? await request(["action": "close", "connection": connection]) }
            connection = nil
            worker = nil
            if active, refreshSession || generation != started { start() }
        }
    }

    private func updateLocation() {
        guard active, let connection, !updating else { return }
        updating = true
        Task {
            var sent: [String: String]
            repeat {
                sent = location
                var action: [String: Any] = sent
                action["action"] = "update"
                action["connection"] = connection
                _ = try? await request(action)
            } while active && self.connection == connection && sent != location
            updating = false
            if active, self.connection != connection { updateLocation() }
        }
    }
}

private struct AtlasPresenceKey: EnvironmentKey {
    static let defaultValue: AtlasPresence? = nil
}

extension EnvironmentValues {
    var atlasPresence: AtlasPresence? {
        get { self[AtlasPresenceKey.self] }
        set { self[AtlasPresenceKey.self] = newValue }
    }
}
