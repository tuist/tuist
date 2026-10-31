#if os(macOS)
import AppKit
import Combine

@MainActor
final class AtlasWorkstation: ObservableObject {
    typealias Request = AtlasEnvironmentRequest
    @Published private(set) var configuration = AtlasWorkstationConfiguration()
    @Published private(set) var ownerId: String?
    @Published private(set) var available = false
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var projects: [AtlasEnvironmentProject] = []
    @Published var message: String?

    private let request: Request
    private let live: Request
    private let keychain: any AtlasKeychainAccess
    private let origin: String
    private let worktrees = AtlasWorkstationWorktrees()
    private var roots: [String: URL] = [:]
    private var generation = UUID()
    private var listener: Task<Void, Never>?
    private var connection: String?
    private var activity: NSObjectProtocol?
    private var executions: [String: Task<Void, Never>] = [:]
    private var received: Set<String> = []

    init(origin: URL, request: @escaping Request, live: @escaping Request,
         keychain: any AtlasKeychainAccess = AtlasSystemKeychain()) {
        self.origin = origin.absoluteString
        self.request = request
        self.live = live
        self.keychain = keychain
    }

    func load() async {
        guard !busy, !available else { return }
        busy = true
        let current = generation
        defer { if generation == current { busy = false } }
        do {
            let overview = try AtlasEnvironmentCoding.decode(
                AtlasEnvironmentOverview.self, from: await request(["action": "list"])
            )
            guard generation == current else { return }
            ownerId = overview.ownerId
            if let stored = try AtlasSecureStorage.load(storageKey(overview.ownerId), keychain: keychain) {
                configuration = try JSONDecoder().decode(AtlasWorkstationConfiguration.self, from: Data(stored.utf8))
                configuration.enabled = configuration.enabled && overview.environments.contains {
                    $0.id == configuration.id && $0.enabled
                }
            }
            let selected = try await AtlasWorkstationProjects.discover(configuration)
            let discoveredProjects = await AtlasWorkstationProjects.metadata(selected)
            guard generation == current else { return }
            roots = selected
            projects = discoveredProjects
            available = true
            message = nil
            if configuration.enabled { start() }
        } catch {
            guard generation == current else { return }
            configuration.enabled = false
            message = error.localizedDescription
        }
    }

    func save(_ draft: AtlasWorkstationConfiguration) async {
        guard available, !busy, let ownerId else { return }
        busy = true
        stop()
        let current = generation
        defer { if generation == current { busy = false } }
        do {
            var next = draft
            next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Persist disabled consent before any network mutation. Failed enabling
            // or a terminated app cannot leave an unconfirmed local opt-in.
            var disabled = next
            disabled.enabled = false
            configuration = disabled
            try persist(disabled, ownerId: ownerId)
            let selected = try await AtlasWorkstationProjects.discover(next)
            let discoveredProjects = await AtlasWorkstationProjects.metadata(selected)
            guard generation == current else { return }
            if next.enabled && selected.isEmpty {
                throw AtlasAuthenticationError(
                    kind: "invalid_request", message: "Choose at least one project or folder first."
                )
            }
            roots = selected
            projects = discoveredProjects
            if next.enabled {
                _ = try await request([
                    "action": "register", "id": next.id, "name": next.name, "enabled": true,
                    "terminal": next.terminal, "display": false,
                    "projects": projects.map {
                        var project: [String: Any] = ["id": $0.id, "name": $0.name, "coding": $0.coding == true]
                        if let repository = $0.repository { project["repository"] = repository }
                        return project
                    }
                ])
            } else {
                _ = try await request(["action": "disable", "id": next.id])
            }
            guard generation == current else { return }
            try persist(next, ownerId: ownerId)
            configuration = next
            message = nil
            if next.enabled { start() }
        } catch {
            guard generation == current else { return }
            message = error.localizedDescription
        }
    }

    func signOut() async {
        invalidate()
        _ = try? await request(["action": "disable", "id": configuration.id])
    }

    func invalidate() {
        stop()
        configuration.enabled = false
        if let ownerId {
            do { try persist(configuration, ownerId: ownerId) } catch {
                try? AtlasSecureStorage.delete(storageKey(ownerId), keychain: keychain)
            }
        }
        available = false
        busy = false
    }

    private func start() {
        let current = generation
        activity = ProcessInfo.processInfo.beginActivity(
            options: configuration.keepAwake
                ? [.userInitiated, .idleSystemSleepDisabled] : [.userInitiatedAllowingIdleSystemSleep],
            reason: "Execute explicitly enabled Atlas environment tools"
        )
        listener = Task { [weak self] in
            guard let self else { return }
            await self.listen(current)
        }
    }

    private func stop() {
        generation = UUID()
        listener?.cancel()
        listener = nil
        executions.values.forEach { $0.cancel() }
        executions = [:]
        received = []
        if let connection {
            let live = live
            Task { _ = try? await live(["action": "close", "connection": connection]) }
        }
        connection = nil
        connected = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func listen(_ current: UUID) async {
        while generation == current, configuration.enabled, !Task.isCancelled {
            do {
                let opened = try await live(["action": "open", "id": configuration.id])
                let value = try JSONSerialization.jsonObject(with: opened) as? [String: Any]
                guard let handle = value?["connection"] as? String else { throw CocoaError(.coderInvalidValue) }
                guard generation == current, !Task.isCancelled else {
                    _ = try? await live(["action": "close", "connection": handle])
                    return
                }
                connection = handle
                var sequence: UInt64 = 0
                while generation == current, !Task.isCancelled {
                    let data = try await live(["action": "next", "connection": handle, "after": sequence])
                    guard generation == current, !Task.isCancelled else { break }
                    let snapshot = try AtlasEnvironmentCoding.decode(AtlasWorkstationSnapshot.self, from: data)
                    sequence = snapshot.sequence ?? sequence
                    if snapshot.needsSession == true { break }
                    connected = snapshot.error == nil
                    if snapshot.error == "unavailable" {
                        throw AtlasAuthenticationError(
                            kind: "unavailable", message: "This environment was disabled or its access changed."
                        )
                    }
                    receive(snapshot.commands ?? [], current: current)
                }
                _ = try? await live(["action": "close", "connection": handle])
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                connected = false
                message = error.localizedDescription
                // Reconcile through the typed HTTP boundary if live delivery is
                // unavailable. Claims remain authoritative and non-replayable.
                if let data = try? await request(["action": "commands", "id": configuration.id]),
                   let snapshot = try? AtlasEnvironmentCoding.decode(AtlasWorkstationSnapshot.self, from: data) {
                    receive(snapshot.commands ?? [], current: current)
                }
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

extension AtlasWorkstation {
    private func receive(_ commands: [AtlasWorkstationCommand], current: UUID) {
        received.formIntersection(Set(commands.map(\.id)).union(executions.keys))
        for command in commands where !received.contains(command.id) && executions.count < 8 {
            guard generation == current, configuration.enabled, !Task.isCancelled else { return }
            received.insert(command.id)
            executions[command.id] = Task { [weak self] in
                guard let self else { return }
                defer { if self.generation == current { self.executions.removeValue(forKey: command.id) } }
                await self.execute(command, current: current)
            }
        }
    }

    private func execute(_ pending: AtlasWorkstationCommand, current: UUID) async {
        guard let root = roots[pending.arguments.projectId], let ownerId,
              (!pending.coding && !pending.terminal) || configuration.terminal,
              !pending.terminal || pending.executionTimeoutSeconds == 1800 else { return }
        do {
            guard generation == current, configuration.enabled, !Task.isCancelled else { return }
            let data = try await request([
                "action": "claim", "id": configuration.id, "command_id": pending.id,
                "digest": pending.digest
            ])
            guard generation == current, configuration.enabled, !Task.isCancelled else { return }
            struct Claimed: Decodable { let command: AtlasWorkstationCommand? }
            let claimed = try AtlasEnvironmentCoding.decode(Claimed.self, from: data)
            guard let command = claimed.command, command.matches(pending), let token = command.claimToken else {
                return
            }
            let progress = AtlasWorkstationProgress()
            let scope = storageKey(ownerId) + ":" + configuration.id
            let execution = Task {
                do {
                    let directory = command.coding
                        ? try await worktrees.directory(for: command, repository: root, scope: scope) : root
                    try Task.checkCancellation()
                    return await AtlasWorkstationExecution.perform(command, root: directory, progress: progress)
                } catch {
                    return AtlasWorkstationResult(
                        success: false, output: "Could not prepare this thread's Git worktree. No tool was executed."
                    )
                }
            }
            let reporter = Task {
                if command.terminal {
                    await report(command, progress: progress, current: current, cancel: { execution.cancel() })
                }
            }
            let result = await withTaskCancellationHandler {
                await execution.value
            } onCancel: { execution.cancel(); reporter.cancel() }
            reporter.cancel()
            guard generation == current, configuration.enabled, !Task.isCancelled else { return }
            // A result upload may be replayed, but never the command itself.
            // Keep the result through transient deploy outages; never rerun the process.
            let completion: [String: Any] = [
                "action": "complete", "id": configuration.id, "command_id": command.id,
                "claim_token": token, "success": result.success, "output": result.output
            ]
            try await deliver(completion, current: current)
        } catch {
            if generation == current { message = error.localizedDescription }
        }
    }

    private func report(_ command: AtlasWorkstationCommand, progress: AtlasWorkstationProgress, current: UUID,
                        cancel: () -> Void) async {
        guard let token = command.claimToken else { return }
        var sequence = 0
        while generation == current, configuration.enabled, !Task.isCancelled {
            sequence += 1
            do {
                let data = try await request([
                    "action": "progress", "id": configuration.id, "command_id": command.id, "claim_token": token,
                    "sequence": sequence, "output": progress.text ?? "[Waiting for UTF-8 output.]"
                ])
                guard generation == current, !Task.isCancelled else { return }
                struct Progress: Decodable { let cancelRequested: Bool }
                if try AtlasEnvironmentCoding.decode(Progress.self, from: data).cancelRequested { cancel(); return }
            } catch {
                if !retryable(error) { cancel(); return }
                if generation == current { message = "Build continues locally. Reconnecting to Atlas…" }
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    private func deliver(_ result: [String: Any], current: UUID) async throws {
        let deadline = ContinuousClock.now + .seconds(300)
        while generation == current, configuration.enabled, !Task.isCancelled {
            do { _ = try await request(result); return } catch {
                guard ContinuousClock.now < deadline, retryable(error) else { throw error }
                message = "Command finished locally. Retrying delivery to Atlas…"
                try await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func retryable(_ error: Error) -> Bool {
        guard !(error is CancellationError) else { return false }
        guard let error = error as? AtlasAuthenticationError else { return true }
        return ["server", "transport", "rate_limited"].contains(error.kind)
    }

    private func storageKey(_ ownerId: String) -> String { "workstation:\(origin):\(ownerId)" }

    private func persist(_ value: AtlasWorkstationConfiguration, ownerId: String) throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.coderInvalidValue) }
        try AtlasSecureStorage.save(storageKey(ownerId), value: text, keychain: keychain)
    }

}
#endif
