import Combine
import Foundation

@MainActor
final class AtlasEnvironmentActivity: ObservableObject {
    @Published private(set) var commands: [AtlasEnvironmentJob] = []
    @Published private(set) var message: String?
    @Published private(set) var busy: Set<String> = []
    private let threadId: String
    private let request: AtlasEnvironmentRequest
    private var generation = UUID()
    private var readRevision = UUID()
    private var active = false

    init(threadId: String, request: @escaping AtlasEnvironmentRequest) {
        self.threadId = threadId
        self.request = request
    }

    func watch() async {
        generation = UUID()
        readRevision = UUID()
        busy = []
        let current = generation
        active = true
        defer { if generation == current { active = false } }
        while generation == current, !Task.isCancelled {
            if !(await refresh()) { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    func stop() {
        active = false
        generation = UUID()
        readRevision = UUID()
        busy = []
    }

    func cancel(_ job: AtlasEnvironmentJob) async {
        guard active, !busy.contains(job.id), commands.contains(where: { $0.id == job.id && $0.digest == job.digest }),
              !Task.isCancelled else { return }
        let current = generation
        readRevision = UUID()
        busy.insert(job.id)
        defer { if generation == current { busy.remove(job.id) } }
        do {
            _ = try await request(["action": "cancel_command", "thread_id": threadId, "command_id": job.id, "digest": job.digest])
            guard generation == current, !Task.isCancelled else { return }
            _ = await refresh()
        } catch {
            if generation == current, !Task.isCancelled { handle(error) }
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        let current = generation
        let revision = UUID()
        readRevision = revision
        do {
            struct Activity: Decodable { let commands: [AtlasEnvironmentJob] }
            let data = try await request(["action": "thread_commands", "thread_id": threadId])
            let activity = try AtlasEnvironmentCoding.decode(Activity.self, from: data)
            guard generation == current, !Task.isCancelled else { return false }
            guard readRevision == revision else { return true }
            if commands != activity.commands { commands = activity.commands }
            message = nil
            return true
        } catch {
            guard generation == current, !Task.isCancelled else { return false }
            guard readRevision == revision else { return true }
            handle(error)
            return !["forbidden", "unavailable", "sign_in_required"].contains((error as? AtlasAuthenticationError)?.kind ?? "")
        }
    }

    private func handle(_ error: Error) {
        if let error = error as? AtlasAuthenticationError,
           ["forbidden", "unavailable", "sign_in_required"].contains(error.kind) {
            commands = []
            message = nil
        } else {
            message = "Mac activity is out of date. Reconnecting…"
        }
    }
}
