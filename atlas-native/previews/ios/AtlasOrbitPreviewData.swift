import Foundation
import SwiftUI

/// Fixture-only snapshots for rendering production thread views offline.
@MainActor
final class AtlasOrbitPreviewData: ObservableObject {
    private var sequence = 0
    private var loads = 0
    private let clock = ContinuousClock()
    private var activityStarted: ContinuousClock.Instant?
    private var followStarted: ContinuousClock.Instant?
    private var rich: Bool { ProcessInfo.processInfo.arguments.contains("--orbit-rich") }
    private var activity: Bool { ProcessInfo.processInfo.arguments.contains("--orbit-activity") }
    private var follow: Bool { ProcessInfo.processInfo.arguments.contains("--orbit-follow") }
    private var selected: [String: Any]?
    private var listKind: String?
    private var listStatus = "active"
    private var archivedIDs: Set<String> = []
    private var createdThreads: [[String: Any]] = []
    private var draft = ""
    private var draftMentions: [[String: String]] = []
    private var mentionCandidates: [[String: String]] = []
    private var mentionsByThread: [String: [[String: String]]] = [:]
    private var promotedIDs: Set<String> = []
    private var draftAttachments: [[String: Any]] = []
    private var sent: [[String: Any]] = []
    private var drafts: [String: String] = [:]
    private var attachmentsByThread: [String: [[String: Any]]] = [:]
    private var sentByThread: [String: [[String: Any]]] = [:]
    private var seededAttachments = false
    private var olderPromptsLoaded = false
    private let promptTime = Date()
    private let attachmentID = "01922cc0-0000-7000-8000-000000000010"
    private let attachmentBytes = Data("Atlas attachment fixture. No private data.\n".utf8)
    private let privateID = "01922cc0-0000-7000-8000-000000000001"
    private let sharedID = "01922cc0-0000-7000-8000-000000000002"
    private let secondPrivateID = "01922cc0-0000-7000-8000-000000000003"

    func request(_ action: [String: Any]) async throws -> Data {
        if action["action"] as? String == "open" { return Data("{\"connection\":\"preview-only\"}".utf8) }
        let command = action["command"] as? [String: Any] ?? [:]
        switch command["action"] as? String {
        case "load":
            listKind = command["kind"] as? String
            if let status = command["status"] as? String { listStatus = status }
            loads += 1
            if loads > 1, ProcessInfo.processInfo.arguments.contains("--fail-orbit-refresh") {
                throw AtlasAuthenticationError(kind: "server", message: "Preview refresh failed. Loaded threads are retained.")
            }
        case "private":
            select(thread(id: privateID, title: "Build listing latency", kind: "private"))
        case "create_private":
            listStatus = "active"
            let created = thread(id: UUID().uuidString.lowercased(), title: "New conversation", kind: "private")
            createdThreads.insert(created, at: 0)
            select(created)
        case "archive":
            if ProcessInfo.processInfo.arguments.contains("--fail-orbit-archive") {
                throw AtlasAuthenticationError(kind: "server", message: "Preview archive failed. Your conversation is still here.")
            }
            if let id = command["id"] as? String {
                let archived = command["archived"] as? Bool == true
                if archived { archivedIDs.insert(id) } else { archivedIDs.remove(id) }
                if selected?["id"] as? String == id { selected?["status"] = archived ? "archived" : "active" }
            }
        case "select":
            if ProcessInfo.processInfo.arguments.contains("--delayed-orbit") { try await Task.sleep(for: .seconds(8)) }
            switch command["id"] as? String {
            case privateID: select(thread(id: privateID, title: "Build listing latency", kind: "private"))
            case secondPrivateID: select(thread(id: secondPrivateID, title: "Release checklist", kind: "private"))
            case sharedID: select(thread(id: sharedID, title: "Build listing latency", kind: "shared"))
            default:
                let available = createdThreads + (AtlasSocialPreviewData.enabled ? AtlasSocialPreviewData.threads : [])
                if let created = available.first(where: { $0["id"] as? String == command["id"] as? String }) {
                    select(created)
                } else {
                    select(nil)
                    throw AtlasAuthenticationError(kind: "unavailable", message: "This thread is no longer available.")
                }
            }
        case "create": select(thread(id: sharedID, title: command["title"] as? String ?? "A new thread", kind: "shared"))
        case "leave": select(nil)
        case "people":
            let query = command["query"] as? String ?? ""
            mentionCandidates = query.isEmpty || "Alex Morgan".localizedCaseInsensitiveContains(query)
                ? [["id": "01922cc0-0000-7000-8000-000000000099", "name": "Alex Morgan"]] : []
        case "history":
            if command["older"] as? Bool == true {
                if ProcessInfo.processInfo.arguments.contains("--delayed-orbit-history") {
                    try await Task.sleep(for: .seconds(8))
                }
                olderPromptsLoaded = true
            }
        case "send":
            var handoff: [String: Any]?
            if !draftMentions.isEmpty, let id = selected?["id"] as? String, !promotedIDs.contains(id) {
                promotedIDs.insert(id)
                selected?["kind"] = "shared"
                if let index = createdThreads.firstIndex(where: { $0["id"] as? String == id }) { createdThreads[index]["kind"] = "shared" }
                handoff = message(id: "handoff-\(sent.count)", kind: "system", body: """
                    Conversation so far — excerpts for new participants (not an AI-generated summary).

                    Initial request (excerpt):
                    > Check whether other projects are affected too.

                    Latest Pip reply (excerpt):
                    > The build listing became slower after this morning’s deployment. I’m comparing the query plans.
                    """, extra: ["notice_kind": "handoff"])
            }
            if sent.isEmpty, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let index = createdThreads.firstIndex(where: { $0["id"] as? String == selected?["id"] as? String }) {
                let title = String(draft.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
                createdThreads[index]["title"] = title
                selected?["title"] = title
            }
            sent.append(message(id: UUID().uuidString, kind: "human", body: draft, extra: [
                "author_id": "preview-self", "author_name": "Taylor", "attachments": draftAttachments
            ]))
            if let handoff { sent.append(handoff) }
            draft = ""
            draftMentions = []
            draftAttachments = []
        case "upload_attachment":
            let bytes = Data(base64Encoded: command["data"] as? String ?? "") ?? Data()
            draftAttachments.append(["id": UUID().uuidString.lowercased(), "filename": command["filename"] as? String ?? "Photo.jpg",
                                     "content_type": command["content_type"] as? String ?? "image/jpeg", "byte_size": bytes.count])
        case "delete_attachment": draftAttachments.removeAll { $0["id"] as? String == command["attachment_id"] as? String }
        case "download_attachment":
            return try JSONSerialization.data(withJSONObject: [
                "thread_id": selected?["id"] as? String ?? "",
                "attachment": ["data": attachmentBytes.base64EncodedString()]
            ])
        default: break
        }
        return try snapshot()
    }

    func local(_ action: [String: Any]) async throws -> Data {
        if action["action"] as? String == "component_action" {
            return try JSONSerialization.data(withJSONObject: [
                "effect": "show_evidence", "thread_id": action["id"] as? String ?? "", "message_id": action["message_id"] as? String ?? ""
            ])
        }
        if action["action"] as? String == "next" {
            try await Task.sleep(for: .seconds(activity || follow ? 1 : 30))
        }
        if action["action"] as? String == "draft" {
            draft = action["body"] as? String ?? ""
            draftMentions.removeAll { !draft.contains("@" + ($0["name"] ?? "")) }
        }
        if action["action"] as? String == "mention",
           let person = mentionCandidates.first(where: { $0["id"] == action["user_id"] as? String }),
           let at = draft.lastIndex(of: "@") {
            draft.replaceSubrange(at..., with: "@" + (person["name"] ?? "") + " ")
            draftMentions.append(person)
            mentionCandidates = []
        }
        return try snapshot()
    }

    private func select(_ next: [String: Any]?) {
        if let id = selected?["id"] as? String {
            drafts[id] = draft
            mentionsByThread[id] = draftMentions
            attachmentsByThread[id] = draftAttachments
            sentByThread[id] = sent
        }
        selected = next
        let id = next?["id"] as? String ?? ""
        draft = drafts[id] ?? ""
        draftMentions = mentionsByThread[id] ?? []
        mentionCandidates = []
        draftAttachments = attachmentsByThread[id] ?? []
        sent = sentByThread[id] ?? []
        activityStarted = clock.now
        followStarted = next == nil ? nil : clock.now
        olderPromptsLoaded = false
    }

    private func snapshot() throws -> Data {
        sequence += 1
        if let id = selected?["id"] as? String {
            drafts[id] = draft
            mentionsByThread[id] = draftMentions
            attachmentsByThread[id] = draftAttachments
            sentByThread[id] = sent
        }
        if activity, selected != nil {
            let elapsed = activityStarted?.duration(to: clock.now).components.seconds ?? 0
            let step = min(3, Int(elapsed / 6))
            selected?["agent_status"] = ["queued", "running", "compacting", "idle"][step]
        }
        var messages: [[String: Any]] = []
        if selected != nil {
            messages = [
                message(id: "message-1", kind: "agent", body: rich ? richBody
                    : "The build listing became slower after this morning’s deployment. I’m comparing the query plans."),
                message(id: "message-2", kind: "tool", body: rich ? "Fetched account details" : "Compared query plans", extra: [
                    "tool_name": rich ? "Account lookup" : "Query plans", "tool_status": "succeeded",
                    "tool_output": rich ? "Northstar · active · enterprise" : "The new filter bypasses the existing index.",
                    "component": ProcessInfo.processInfo.arguments.contains("--legacy-thread-cards") ? NSNull() : [
                        "type": rich ? "account_card" : "result_table", "version": 1,
                        "data": rich ? ["title": "Northstar", "columns": ["Field", "Value"],
                                        "rows": [["Domain", "northstar.example"], ["Status", "active"], ["Segment", "enterprise"]]]
                            : ["title": "Query comparison", "columns": ["Finding", "Impact"],
                               "rows": [["The new filter bypasses the existing index.", "2.4× slower"]]],
                        "actions": [["id": "show_evidence", "label": "View source"]],
                        "fallback": rich ? "Northstar · active · enterprise" : "The new filter bypasses the existing index."
                    ] as Any
                ]),
                message(id: "message-3", kind: "human", body: rich ? "Check recent activity for this account."
                    : "Check whether other projects are affected too.", extra: [
                    "author_id": "preview-self", "author_name": "Taylor"
                ])
            ]
            if selected?["kind"] as? String == "shared" {
                messages.insert(message(id: "message-alex", kind: "human", body: "I noticed it on the dashboard as well.", extra: [
                    "author_id": "online", "author_name": "Alex"
                ]), at: 0)
            } else if ProcessInfo.processInfo.arguments.contains("--empty-private") {
                messages = []
            } else if selected?["id"] as? String == secondPrivateID {
                messages = [
                    message(id: "release-question", kind: "human", body: "Help me prepare a release checklist.", extra: [
                        "author_id": "preview-self", "author_name": "Taylor"
                    ]),
                    message(id: "release-reply", kind: "agent", body: "Start with validation, release notes, and a rollback plan.")
                ]
            }
            if ProcessInfo.processInfo.arguments.contains("--orbit-tool-tree") { messages = toolTree }
            if ProcessInfo.processInfo.arguments.contains("--orbit-attachments") {
                let attachment: [String: Any] = ["id": attachmentID, "filename": "notes.txt", "content_type": "text/plain",
                                                  "byte_size": attachmentBytes.count]
                messages = [message(id: "attached-message", kind: "human", body: "Review these notes.", extra: [
                    "author_id": "preview-self", "author_name": "Taylor", "attachments": [attachment]
                ])]
                if !seededAttachments { draftAttachments = [attachment]; seededAttachments = true }
            }
            if ProcessInfo.processInfo.arguments.contains("--orbit-prompts") { messages = promptHistory }
            if ProcessInfo.processInfo.arguments.contains("--orbit-long-history") { messages = longHistory }
            if AtlasSocialPreviewData.enabled { messages = AtlasSocialPreviewData.messages(threadID: selected?["id"] as? String ?? "") }
            if createdThreads.contains(where: { $0["id"] as? String == selected?["id"] as? String }) { messages = [] }
            messages += sent
            if follow, let followStarted {
                let elapsed = followStarted.duration(to: clock.now).components.seconds
                selected?["agent_status"] = elapsed < 6 ? "queued" : (elapsed < 18 ? "running" : "idle")
                if elapsed >= 6 {
                    let steps = min(12, max(0, Int(elapsed - 9) * 2))
                    var body = "A new reply appeared."
                    if steps > 0 {
                        body += "\n\n" + (1...steps).map {
                            "Step \($0): Compare the fixture evidence, validate the affected projects, and keep the rollout reversible."
                        }.joined(separator: "\n\n")
                    }
                    if elapsed >= 18 { body += "\n\nThe growing reply is complete." }
                    messages.append(message(id: "follow-reply", kind: "agent", body: body))
                }
            }
        }
        let seedThreads = AtlasSocialPreviewData.enabled ? AtlasSocialPreviewData.threads : [
            thread(id: privateID, title: "Build listing latency", kind: "private"),
            thread(id: secondPrivateID, title: "Release checklist", kind: "private"),
            thread(id: sharedID, title: "Build listing latency", kind: "shared")
        ]
        let threads = (createdThreads + seedThreads).map { value in
            var thread = value
            thread["status"] = archivedIDs.contains(value["id"] as? String ?? "") ? "archived" : "active"
            return thread
        }
        return try JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "assistant": ["name": "Pip", "configured": true],
            "threads": threads.filter { (listKind == nil || $0["kind"] as? String == listKind) && $0["status"] as? String == listStatus },
            "status_filter": listStatus,
            "selection_id": selected?["id"] as Any? ?? NSNull(),
            "selected": selected as Any? ?? NSNull(), "messages": messages,
            "people": selected?["kind"] as? String == "shared" ? [["id": "online", "name": "Alex", "typing": false]] : [],
            "draft": draft, "draft_mentions": draftMentions, "mention_candidates": mentionCandidates,
            "draft_attachments": draftAttachments, "attachment_busy": false,
            "has_drafts": !draft.isEmpty || !draftAttachments.isEmpty || drafts.values.contains(where: { !$0.isEmpty }),
            "loading": false, "history_loading": false, "saving": false,
            "has_more": false, "has_older": ProcessInfo.processInfo.arguments.contains("--orbit-prompts") && !olderPromptsLoaded,
            "needs_session": false
        ])
    }

    private var promptHistory: [[String: Any]] {
        let prompts = ["", "Summarize this week's build activity.", "Which projects need attention?", "Compare the recent errors.",
                       "Check the build listing query plan.", "Does it affect other projects?", "Review the proposed index.",
                       "What are the rollout risks?", "Include a concise validation checklist.", "Summarize the next steps."]
        return prompts.indices.filter { olderPromptsLoaded || $0 >= 4 }.flatMap { index in
            let date = ISO8601DateFormatter().string(from: promptTime.addingTimeInterval(Double(index - 12) * 300))
            let own = selected?["kind"] as? String == "private" || index.isMultiple(of: 2)
            var extra: [String: Any] = ["author_id": own ? "preview-self" : "online",
                                        "author_name": own ? "Taylor" : "Alex", "inserted_at": date]
            if index == 0 {
                extra["attachments"] = [["id": attachmentID, "filename": "release-notes.txt",
                                          "content_type": "text/plain", "byte_size": attachmentBytes.count]]
            }
            let prompt = message(id: "prompt-\(index)", kind: "human", body: prompts[index], extra: extra)
            if index == prompts.count - 1 { return [prompt] }
            return [prompt, message(id: "reply-\(index)", kind: "agent", body: """
                    I checked the fixture data for this step. The build listing uses a different query plan after the latest filter change.

                    The next step is to compare affected projects and confirm the index covers the new filter before rolling it out.
                    """, extra: ["inserted_at": date])]
        }
    }

    private lazy var longHistory: [[String: Any]] = {
        (0..<120).flatMap { index -> [[String: Any]] in
            var rows = [self.message(id: "long-prompt-\(index)", kind: "human", body: "Review evidence for step \(index).", extra: [
                "author_id": "preview-self", "author_name": "Taylor"
            ])]
            if index.isMultiple(of: 3) {
                rows += (0..<4).map { tool in
                    self.message(id: "long-tool-\(index)-\(tool)", kind: "tool", body: "", extra: [
                        "tool_name": "get_builds", "tool_status": "succeeded", "tool_output": "Offline fixture evidence."
                    ])
                }
            }
            let paragraphs = (0..<(index == 119 ? 16 : index % 4 + 1)).map { paragraph in
                "Evidence \(index).\(paragraph): **Compare the affected projects**, validate the query plan, and retain a rollback path."
            }.joined(separator: "\n\n")
            rows.append(self.message(id: "long-reply-\(index)", kind: "agent", body: paragraphs +
                (index == 119 ? "\n\nThe long conversation is still visible." : "")))
            return rows
        }
    }()

    private var toolTree: [[String: Any]] {
        let parent = "01922cc0-0000-7000-8000-000000000020"
        return [
            message(id: "research-intro", kind: "agent", body: "I delegated a focused research task."),
            message(id: parent, kind: "tool", body: "", extra: [
                "tool_name": "research", "tool_status": "succeeded", "tool_input": "Compare recent build errors.",
                "tool_output": "The fixture investigation found two affected projects."
            ]),
            message(id: "01922cc0-0000-7000-8000-000000000021", kind: "tool", body: "", extra: [
                "tool_name": "list_error_issues", "tool_status": "succeeded", "parent_message_id": parent,
                "tool_output": "Two fixture issues, both related to indexing."
            ]),
            message(id: "01922cc0-0000-7000-8000-000000000022", kind: "tool", body: "", extra: [
                "tool_name": "list_engineering_projects", "tool_status": "succeeded", "parent_message_id": parent,
                "tool_output": "Two fixture projects. No private data."
            ]),
            message(id: "research-result", kind: "agent", body: "The two fixture projects share the same indexing change.")
        ]
    }

    private var richBody: String {
        """
        ## Account overview
        **Northstar** is an active enterprise account.

        - Review the account's recent activity
        - Compare the latest build results

        > Only authorized source data appears in this card.

        ```swift
        let account = "Northstar"
        ```
        """
    }

    private func thread(id: String, title: String, kind: String) -> [String: Any] {
        if AtlasSocialPreviewData.enabled, var social = AtlasSocialPreviewData.threads.first(where: { $0["id"] as? String == id }) {
            social["status"] = archivedIDs.contains(id) ? "archived" : "active"
            return social
        }
        let updated = id == secondPrivateID ? Calendar.current.date(byAdding: .day, value: -1, to: promptTime)! : promptTime
        return ["id": id, "title": title, "kind": promotedIDs.contains(id) ? "shared" : kind,
         "status": archivedIDs.contains(id) ? "archived" : "active",
         "summary": kind == "shared" ? "Comparing query plans across affected projects." : "",
         "origin": kind == "private" ? "manual" : "signal", "owner_id": "preview-self", "participants": [["id": "preview-self", "name": "Taylor"]],
         "updated_at": ISO8601DateFormatter().string(from: updated)]
    }

    private func message(id: String, kind: String, body: String, extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["id": id, "kind": kind, "body": body, "author_name": "Pip", "inserted_at": "2027-06-07T10:42:00Z", "tool_input": "", "tool_output": ""]
        for (key, field) in extra { value[key] = field }
        return value
    }
}
