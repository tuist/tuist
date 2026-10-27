import Foundation
import SwiftUI

@MainActor
final class AtlasSharedItems: ObservableObject {
    @Published private(set) var items: [AtlasShareCapture] = []
    @Published var draft: AtlasShareCapture?
    @Published var presented = false
    @Published private(set) var saving = false
    @Published private(set) var suggesting = false
    @Published var errorMessage: String?
    @Published private(set) var suggestionMessage: String?

    private let inbox: AtlasShareInbox
    private let recipient: AtlasShareRecipient
    private let request: ([String: Any]) async throws -> Data
    private var suggested: Set<UUID> = []
    private var generation = 0

    init(inbox: AtlasShareInbox, recipient: AtlasShareRecipient,
         request: @escaping ([String: Any]) async throws -> Data) {
        self.inbox = inbox
        self.recipient = recipient
        self.request = request
    }

    func reload() {
        do { items = try inbox.captures(for: recipient) } catch { errorMessage = error.localizedDescription }
    }

    func select(_ item: AtlasShareCapture) {
        guard !saving else { return }
        persistDraft()
        generation += 1
        suggesting = false
        draft = item
        errorMessage = nil
        suggestionMessage = nil
    }

    func persistDraft() {
        guard let draft else { return }
        do { try inbox.save(draft); reload() } catch { errorMessage = error.localizedDescription }
    }

    func suggest() async {
        guard let initial = draft, !initial.submitted, !suggested.contains(initial.id) else { return }
        suggested.insert(initial.id)
        let generation = generation
        suggesting = true
        defer { if self.generation == generation { suggesting = false } }
        do {
            let data = try await request(["action": "suggest", "url": initial.url, "content": initial.content])
            let result = try JSONDecoder().decode(Suggested.self, from: data)
            guard self.generation == generation, draft?.id == initial.id, draft?.submitted == false else { return }
            // Field-by-field comparison preserves typing that happened during inference.
            if initial.title.isEmpty, draft?.title == initial.title { draft?.title = result.suggestions.title }
            if initial.description.isEmpty, draft?.description == initial.description {
                draft?.description = result.suggestions.description
            }
            if initial.tags.isEmpty, draft?.tags == initial.tags { draft?.tags = result.suggestions.tags }
            suggestionMessage = result.suggestions.generated
                ? "AI suggestions — review before saving."
                : "Using available page details. AI suggestions are unavailable."
            persistDraft()
        } catch is CancellationError {} catch {
            guard self.generation == generation else { return }
            suggestionMessage = "Suggestions are unavailable. You can fill in the fields and save."
        }
    }

    func save() async {
        guard var capture = draft, !saving, !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true
        generation += 1
        suggesting = false
        errorMessage = nil
        defer { saving = false }
        do {
            if !capture.submitted {
                capture.tags = capture.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            capture.submitted = true
            try inbox.save(capture)
            draft = capture
            let data = try await request(["action": "capture", "request_id": capture.id.uuidString.lowercased(),
                                          "attributes": capture.attributes])
            let response = try JSONDecoder().decode(Captured.self, from: data)
            guard response.saved, UUID(uuidString: response.resourceId) != nil else { throw AtlasShareError.unavailable }
            try inbox.remove(capture.id)
            draft = nil
            reload()
        } catch {
            // A definitive validation failure made no write; allow correcting fields.
            if let failure = error as? AtlasAuthenticationError, failure.kind == "invalid_capture" {
                capture.submitted = false
                draft = capture
                persistDraft()
            }
            errorMessage = error.localizedDescription
        }
    }

    func discard() {
        guard let draft, !saving else { return }
        do {
            try inbox.remove(draft.id)
            self.draft = nil
            generation += 1
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func leaveEditor() {
        guard !saving else { return }
        persistDraft()
        draft = nil
        generation += 1
    }

    func invalidate() {
        generation += 1
        items = []
        draft = nil
        presented = false
    }
}

private struct Suggested: Decodable {
    struct Fields: Decodable { let title: String; let description: String; let tags: [String]; let generated: Bool }
    let suggestions: Fields
}

private struct Captured: Decodable {
    let saved: Bool
    let resourceId: String
    enum CodingKeys: String, CodingKey { case saved; case resourceId = "resource_id" }
}
