import Foundation
import SwiftUI

struct AtlasThreadPerson: Decodable, Identifiable {
    let id: String
    let name: String
}

struct AtlasThread: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let status: String
    let summary: String
    let origin: String
    let ownerId: String?
    let participants: [AtlasThreadPerson]
    let updatedAt: String
    let agentStatus: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AtlasThreadComponent: Codable {
    struct Table: Codable {
        let title: String
        let columns: [String]
        let rows: [[String]]
    }
    struct Action: Codable {
        let id: String
        let label: String
    }
    let type: String
    let version: Int
    let data: Table
    let actions: [Action]
    let fallback: String
}

struct AtlasThreadAttachment: Decodable, Identifiable, Equatable {
    let id: String
    let filename: String
    let contentType: String
    let byteSize: Int
}

struct AtlasThreadMessage: Decodable, Identifiable {
    let id: String
    let kind: String
    let body: String
    let authorId: String?
    let authorName: String
    let insertedAt: String
    let toolName: String?
    let toolStatus: String?
    let parentMessageId: String?
    let toolInput: String
    let toolOutput: String
    let component: AtlasThreadComponent?
    let attachments: [AtlasThreadAttachment]?
}

struct AtlasOrbitAssistant: Decodable {
    let name: String
    let configured: Bool
}

/// UI adapter only. Rust owns the feature state, networking, pagination,
/// reconciliation, drafts, idempotency keys and live thread lifecycle.
@MainActor
final class AtlasOrbit: ObservableObject {
    struct Viewer: Decodable, Identifiable {
        let id: String
        let name: String
        let typing: Bool
    }
    struct Snapshot: Decodable {
        let sequence: UInt64
        let assistant: AtlasOrbitAssistant?
        let threads: [AtlasThread]
        let selected: AtlasThread?
        let messages: [AtlasThreadMessage]
        let people: [Viewer]
        let draft: String
        let draftAttachments: [AtlasThreadAttachment]?
        let attachmentBusy: Bool?
        let uploadPending: Bool?
        let uploadFilename: String?
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
    @Published private var attaching = false
    @Published var draft = "" {
        didSet { if !applyingDraft { writeDraft() } }
    }
    var assistant: AtlasOrbitAssistant? { state?.assistant }
    var threads: [AtlasThread] { state?.threads ?? [] }
    var selected: AtlasThread? { state?.selected }
    var messages: [AtlasThreadMessage] { state?.messages ?? [] }
    var viewers: [Viewer] { state?.people ?? [] }
    var draftAttachments: [AtlasThreadAttachment] { state?.draftAttachments ?? [] }
    var attachmentBusy: Bool { attaching || state?.attachmentBusy == true }
    var pendingUploadName: String? { state?.uploadPending == true ? state?.uploadFilename : nil }
    var loading: Bool { state?.loading ?? false }
    var loadingHistory: Bool { state?.historyLoading ?? false }
    var saving: Bool { submitting || (state?.saving ?? false) }
    var creating: Bool { loading }
    var hasMore: Bool { state?.hasMore ?? false }
    var hasOlder: Bool { state?.hasOlder ?? false }
    var errorMessage: String? { adapterError ?? state?.error }
    var liveMessage: String? { state?.liveMessage }
    var activeToolName: String? {
        guard selected?.agentStatus == "running" else { return nil }
        let name = messages.last { $0.kind == "tool" && $0.toolStatus == "running" }?.toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
    var activityMessage: String? {
        guard liveMessage == nil else { return nil }
        let name = assistant?.name ?? "Pip"
        switch selected?.agentStatus {
        case "queued": return "\(name) is getting ready…"
        case "running":
            if let tool = activeToolName { return "Using \(tool.replacingOccurrences(of: "_", with: " "))…" }
            return "Typing…"
        case "compacting": return "Compacting context…"
        default: return nil
        }
    }

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

    func privateThread() async -> AtlasThread? {
        guard await perform(["action": "private"]) else { return nil }
        return selected
    }

    func create(title: String, participants: [String]) async -> AtlasThread? {
        guard await perform(["action": "create", "title": title, "participant_ids": participants]) else { return nil }
        return state?.error == nil ? selected : nil
    }

    func open(_ thread: AtlasThread) async {
        if selected?.id != thread.id { await perform(["action": "select", "id": thread.id]) }
    }

    func open(id: String) async -> AtlasThread? {
        guard await perform(["action": "select", "id": id]), !Task.isCancelled,
              let selected, selected.id == id else { return nil }
        return selected
    }

    func leave(id: String) {
        Task {
            await draftTask?.value
            await perform(["action": "leave", "id": id])
        }
    }

    func history(older: Bool = false) async { await perform(["action": "history", "older": older]) }

    func send(addressAgent: Bool) async {
        guard !saving, !attachmentBusy, let id = selected?.id else { return }
        submitting = true
        defer { submitting = false }
        let body = draft
        await draftTask?.value
        await perform(["action": "send", "id": id, "body": body, "address_agent": addressAgent])
    }

    func upload(filename: String, contentType: String, data: Data) async {
        guard !saving, !attachmentBusy, let id = selected?.id else { return }
        attaching = true
        defer { attaching = false }
        await perform(["action": "upload_attachment", "id": id,
                       "filename": filename, "content_type": contentType, "data": data.base64EncodedString()])
    }

    func resolveUpload(retry: Bool) async {
        guard !saving, !attachmentBusy, let id = selected?.id else { return }
        attaching = true
        defer { attaching = false }
        await perform(["action": retry ? "retry_upload" : "discard_upload", "id": id])
    }

    func removeAttachment(_ attachment: AtlasThreadAttachment) async {
        guard !saving, !attachmentBusy, let id = selected?.id else { return }
        attaching = true
        defer { attaching = false }
        await perform(["action": "delete_attachment", "id": id, "attachment_id": attachment.id])
    }

    func download(_ attachment: AtlasThreadAttachment) async -> Data? {
        struct Download: Decodable {
            struct File: Decodable { let data: String }
            let threadId: String
            let attachment: File
        }
        guard let id = selected?.id else { return nil }
        do {
            let handle = try await ensureConnection()
            let response: Download = try decode(await request([
                "action": "request", "connection": handle,
                "command": ["action": "download_attachment", "id": id, "attachment_id": attachment.id]
            ]))
            try Task.checkCancellation()
            guard selected?.id == id, response.threadId == id,
                  let data = Data(base64Encoded: response.attachment.data), data.count == attachment.byteSize else { return nil }
            return data
        } catch is CancellationError { return nil } catch {
            adapterError = error.localizedDescription
            return nil
        }
    }

    func componentAction(messageId: String, event: String) async -> Bool {
        guard let connection, let id = selected?.id else { return false }
        struct Effect: Decodable {
            let effect: String
            let threadId: String
            let messageId: String
        }
        do {
            let effect: Effect = try decode(await localRequest([
                "action": "component_action", "connection": connection, "id": id, "message_id": messageId, "event": event
            ]))
            return selected?.id == id && effect.threadId == id && effect.messageId == messageId
                && effect.effect == "show_evidence" && messages.contains { $0.id == messageId }
        } catch { return false }
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
