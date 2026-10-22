import Foundation
import SwiftUI

struct AtlasConversationPerson: Decodable, Identifiable {
    let id: String
    let name: String
}

struct AtlasConversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let status: String
    let summary: String
    let origin: String
    let ownerId: String?
    let participants: [AtlasConversationPerson]
    let updatedAt: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AtlasConversationMessage: Decodable, Identifiable {
    let id: String
    let kind: String
    let body: String
    let authorId: String?
    let authorName: String
    let insertedAt: String
    let toolName: String?
    let toolStatus: String?
    let toolInput: String
    let toolOutput: String
}

struct AtlasConversationBot: Decodable {
    let name: String
    let configured: Bool
}

/// UI adapter only. Rust owns the feature state, networking, pagination,
/// reconciliation, drafts, idempotency keys and live conversation lifecycle.
@MainActor
final class AtlasConversations: ObservableObject {
    struct Viewer: Decodable, Identifiable {
        let id: String
        let name: String
        let typing: Bool
    }
    struct Snapshot: Decodable {
        let sequence: UInt64
        let bot: AtlasConversationBot?
        let conversations: [AtlasConversation]
        let selected: AtlasConversation?
        let messages: [AtlasConversationMessage]
        let people: [Viewer]
        let draft: String
        let loading: Bool
        let historyLoading: Bool
        let saving: Bool
        let hasMore: Bool
        let hasOlder: Bool
        let error: String?
        let liveMessage: String?
        let needsSession: Bool
    }
    private struct Opened: Decodable { let connection: String }

    @Published private var state: Snapshot?
    @Published private var adapterError: String?
    @Published private var submitting = false
    @Published var draft = "" {
        didSet { if !applyingDraft { writeDraft() } }
    }
    var bot: AtlasConversationBot? { state?.bot }
    var conversations: [AtlasConversation] { state?.conversations ?? [] }
    var selected: AtlasConversation? { state?.selected }
    var messages: [AtlasConversationMessage] { state?.messages ?? [] }
    var viewers: [Viewer] { state?.people ?? [] }
    var loading: Bool { state?.loading ?? false }
    var loadingHistory: Bool { state?.historyLoading ?? false }
    var saving: Bool { submitting || (state?.saving ?? false) }
    var creating: Bool { loading }
    var hasMore: Bool { state?.hasMore ?? false }
    var hasOlder: Bool { state?.hasOlder ?? false }
    var errorMessage: String? { adapterError ?? state?.error }
    var liveMessage: String? { state?.liveMessage }

    private let request: ([String: Any]) async throws -> Data
    private let localRequest: ([String: Any]) async throws -> Data
    private var connection: String?
    private var opening: Task<String, Error>?
    private var listener: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var active = false
    private var applyingDraft = false
    private var pendingDrafts = 0

    init(request: @escaping ([String: Any]) async throws -> Data,
         localRequest: @escaping ([String: Any]) async throws -> Data) {
        self.request = request
        self.localRequest = localRequest
    }

    deinit {
        listener?.cancel()
        if let connection {
            let close = localRequest
            Task { _ = try? await close(["action": "close", "connection": connection]) }
        }
    }

    func load(more: Bool = false) async { await perform(["action": more ? "load_more" : "load"]) }

    func privateConversation() async -> AtlasConversation? {
        guard await perform(["action": "private"]) else { return nil }
        return selected
    }

    func create(title: String, participants: [String]) async -> AtlasConversation? {
        guard await perform(["action": "create", "title": title, "participant_ids": participants]) else { return nil }
        return state?.error == nil ? selected : nil
    }

    func open(_ conversation: AtlasConversation) async {
        if selected?.id != conversation.id { await perform(["action": "select", "id": conversation.id]) }
    }

    func leave(id: String) {
        Task {
            await draftTask?.value
            await perform(["action": "leave", "id": id])
        }
    }

    func history(older: Bool = false) async { await perform(["action": "history", "older": older]) }

    func send(addressAgent: Bool) async {
        guard !submitting, let id = selected?.id else { return }
        submitting = true
        defer { submitting = false }
        let body = draft
        await draftTask?.value
        await perform(["action": "send", "id": id, "body": body, "address_agent": addressAgent])
    }

    func setActive(_ value: Bool) {
        active = value
        if !value { listener?.cancel(); listener = nil }
        let previous = lifecycleTask
        lifecycleTask = Task {
            await previous?.value
            guard active == value, let connection else { return }
            do {
                apply(try decode(await localRequest(["action": "active", "connection": connection, "active": value])))
                if active { listen() }
            } catch { adapterError = error.localizedDescription }
        }
    }

    private func ensureConnection() async throws -> String {
        if let connection { return connection }
        if let opening { return try await opening.value }
        let task = Task {
            let opened: Opened = try decode(await request(["action": "open"]))
            return opened.connection
        }
        opening = task
        defer { opening = nil }
        let handle = try await task.value
        connection = handle
        if active {
            apply(try decode(await localRequest(["action": "active", "connection": handle, "active": true])))
            listen()
        }
        return handle
    }

    @discardableResult private func perform(_ command: [String: Any]) async -> Bool {
        do {
            let handle = try await ensureConnection()
            let snapshot: Snapshot = try decode(await request(["action": "request", "connection": handle, "command": command]))
            apply(snapshot)
            adapterError = nil
            return snapshot.error == nil
        } catch is CancellationError { return false } catch {
            adapterError = error.localizedDescription
            return false
        }
    }

    private func writeDraft() {
        guard let connection, let id = selected?.id else { return }
        let body = draft
        let previous = draftTask
        pendingDrafts += 1
        draftTask = Task {
            await previous?.value
            do {
                let snapshot: Snapshot = try decode(await localRequest([
                    "action": "draft", "connection": connection, "id": id, "body": body
                ]))
                pendingDrafts -= 1
                apply(snapshot)
            } catch {
                pendingDrafts -= 1
                adapterError = error.localizedDescription
            }
        }
    }

    private func listen() {
        guard active, listener == nil, let connection else { return }
        listener = Task {
            while !Task.isCancelled, active {
                do {
                    let snapshot: Snapshot = try decode(await localRequest([
                        "action": "next", "connection": connection, "after": state?.sequence ?? 0
                    ]))
                    try Task.checkCancellation()
                    apply(snapshot)
                    if snapshot.needsSession { await perform(["action": "refresh"]) }
                } catch is CancellationError { break } catch {
                    adapterError = error.localizedDescription
                    break
                }
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        guard snapshot.sequence >= (state?.sequence ?? 0) else { return }
        state = snapshot
        if pendingDrafts == 0 {
            applyingDraft = true
            draft = snapshot.draft
            applyingDraft = false
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
