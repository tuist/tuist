import Foundation
import Testing

@MainActor
struct AtlasOrbitTests {
    private let id = "01922cc0-0000-7000-8000-000000000001"
}

extension AtlasOrbitTests {
    @Test(arguments: ["2026-10-24T12:34:56.123456Z", "2026-10-24T12:34:56Z"])
    func conversationDatesAcceptServerMicrosecondsAndLegacySeconds(timestamp: String) async throws {
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"date-handle\"}".utf8) }
            return try snapshot(sequence: 1, updatedAt: timestamp)
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        let date = try #require(model.threads.first?.updatedDate)
        let expected = 1_792_845_296.0 + (timestamp.contains(".") ? 0.123456 : 0)
        #expect(abs(date.timeIntervalSince1970 - expected) < 0.001)
    }

    @Test func bottomFollowingSurvivesLayoutCorrectionsButStopsForUserHistoryScrolling() {
        let state = AtlasThreadScrollState()
        let update = { (metrics: AtlasThreadScrollMetrics) in state.update(metrics) }
        state.userScrolling = false
        #expect(!update(.init(height: 2000, bottom: 600, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 840, viewport: 600)))
        // A later lazy-row correction can change offset without changing the new content height.
        #expect(update(.init(height: 2200, bottom: 880, viewport: 600)))
        #expect(state.following)
        #expect(!update(.init(height: 2200, bottom: 600, viewport: 600)))
        state.userScrolling = true
        #expect(!update(.init(height: 2200, bottom: 645, viewport: 600)))
        state.userScrolling = false
        #expect(!update(.init(height: 2500, bottom: 945, viewport: 600)))
        #expect(!state.following)
        #expect(!update(.init(height: 2500, bottom: 600, viewport: 600)))
        #expect(state.following)
        #expect(update(.init(height: 2500, bottom: 760, viewport: 400, inset: 200)))
        #expect(state.following)
        // Lazy estimates can leave every message above the viewport, not at its bottom edge.
        #expect(update(.init(height: 2500, bottom: 50, viewport: 400, inset: 200)))
        #expect(update(.init(height: 2500, bottom: -30, viewport: 400, inset: 200)))
        #expect(!update(.init(height: 2500, bottom: 400, viewport: 400, inset: 200)))
    }

    @Test func fallbackScrollAccumulatesSlowMovementAndRebasesContentGrowth() {
        let state = AtlasThreadScrollState()
        let update = { (metrics: AtlasThreadScrollMetrics) in state.update(metrics) }
        #expect(!update(.init(height: 2000, bottom: 600, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 840, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 880, viewport: 600)))
        #expect(state.following)
        #expect(!update(.init(height: 2200, bottom: 600, viewport: 600)))
        for step in 1...50 { _ = state.update(.init(height: 2200, bottom: 600 + CGFloat(step) / 2, viewport: 600)) }
        #expect(!state.following)
    }
}

extension AtlasOrbitTests {
    @Test func adapterForwardsCommandsAndRendersRustState() async throws {
        var commands: [String] = []
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            #expect(action["connection"] as? String == "local-handle")
            let command = try #require(action["command"] as? [String: Any])
            let name = try #require(command["action"] as? String)
            commands.append(name)
            return try snapshot(sequence: commands.count, selected: name == "private")
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.assistant?.name == "Pip")
        #expect(model.hasMore)
        #expect(model.threads.first?.id == id)
        let thread = try #require(await model.privateThread())
        await model.open(thread)
        #expect(commands == ["load", "private"])
        #expect(model.selected?.id == id)
    }

    @Test func conversationListAndDistinctCreationUseRustOwnedContract() async throws {
        var commands: [[String: Any]] = []
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            commands.append(command)
            return try snapshot(sequence: commands.count, selected: command["action"] as? String == "create_private")
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        await model.load(more: true)
        #expect(commands[0]["action"] as? String == "load")
        #expect(commands[0]["kind"] == nil)
        #expect(commands[1]["action"] as? String == "load_more")
        #expect(await model.newPrivateThread()?.id == id)
        #expect(commands[2]["action"] as? String == "create_private")
        #expect(commands[2].count == 1) // Replay UUID and owner identity belong to Rust/server.
    }

    @Test func mentionSelectionUsesRustIdentityAndRetainsTheEditableDraft() async throws {
        let personId = "01922cc0-0000-7000-8000-000000000099"
        var sequence = 0
        var body = ""
        var fields: [String: Any] = [:]
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"mention-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            sequence += 1
            if command["action"] as? String == "people" {
                #expect(command["id"] as? String == id)
                #expect(command["query"] as? String == "Al")
                #expect(body == "Please review @Al")
                fields["mention_candidates"] = [["id": personId, "name": "Alex Morgan"]]
            }
            if command["action"] as? String == "send" {
                #expect(command["mention_ids"] as? [String] == [personId])
            }
            return try snapshot(sequence: sequence, selected: true, draft: body, fields: fields)
        }, localRequest: { action in
            sequence += 1
            if action["action"] as? String == "draft" { body = action["body"] as? String ?? "" }
            if action["action"] as? String == "mention" {
                #expect(action["id"] as? String == id)
                #expect(action["user_id"] as? String == personId)
                #expect(action["name"] == nil)
                body = "Please review @Alex Morgan "
                fields["draft_mentions"] = [["id": personId, "name": "Alex Morgan"]]
            }
            return try snapshot(sequence: sequence, selected: true, draft: body, fields: fields)
        })
        _ = await model.open(id: id)
        model.draft = "Please review @Al"
        await model.searchPeople(query: "Al")
        let person = try #require(model.mentionCandidates.first)
        await model.mention(person)
        #expect(model.draft == "Please review @Alex Morgan ")
        #expect(model.draftMentions.map(\.id) == [personId])
        await model.send(addressAgent: false)
    }
}

extension AtlasOrbitTests {
    @Test func aNewerSelectionSupersedesPendingConversationCreation() async throws {
        var pending: CheckedContinuation<Data, Error>?
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            if command["action"] as? String == "create_private" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return try snapshot(sequence: 2, selected: true)
        }, localRequest: { _ in throw CancellationError() })
        let creation = Task { await model.newPrivateThread() }
        while pending == nil { await Task.yield() }
        #expect(await model.open(id: id)?.id == id)
        pending?.resume(returning: try snapshot(sequence: 3, selected: true))
        #expect(await creation.value == nil)
        #expect(model.selected?.id == id)
    }

    @Test func linkedThreadOpensWithoutLoadingAListAndRejectsADifferentSelection() async throws {
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            #expect(command["action"] as? String == "select")
            return try snapshot(sequence: 1, selected: true)
        }, localRequest: { _ in throw CancellationError() })
        #expect(model.threads.isEmpty)
        #expect(await model.open(id: id)?.id == id)
        #expect(await model.open(id: "01922cc0-0000-7000-8000-000000000002") == nil)
    }

    @Test func attachmentDownloadKeepsBytesOnlyForTheAuthorizedSelection() async throws {
        var revoked = false
        var delayed = false
        var pending: CheckedContinuation<Data, Error>?
        let bytes = Data("Private file".utf8)
        let attachment = AtlasThreadAttachment(id: "01922cc0-0000-7000-8000-000000000003", filename: "notes.txt",
                                               contentType: "text/plain", byteSize: bytes.count)
        let response = try JSONSerialization.data(withJSONObject: [
            "thread_id": id, "attachment": ["data": bytes.base64EncodedString()]
        ])
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"handle\"}".utf8) }
            let command = action["command"] as? [String: Any]
            if command?["action"] as? String == "download_attachment" {
                if delayed { return try await withCheckedThrowingContinuation { pending = $0 } }
                return response
            }
            return try snapshot(sequence: revoked ? 2 : 1, selected: !revoked)
        }, localRequest: { _ in throw CancellationError() })
        _ = await model.open(id: id)
        #expect(await model.download(attachment) == bytes)
        delayed = true
        let download = Task { await model.download(attachment) }
        while pending == nil { await Task.yield() }
        revoked = true
        await model.load()
        pending?.resume(returning: response)
        #expect(await download.value == nil)
    }

    @Test(arguments: [0, 5 * 1024 * 1024, 5 * 1024 * 1024 + 1])
    func pickedFilesRejectEmptyAndOversizedDataWithoutTruncation(size: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.txt")
        let data = Data(repeating: 0x31, count: size)
        try data.write(to: url)
        if size == 5 * 1024 * 1024 {
            let file = try AtlasAttachmentFile.read(url)
            #expect(file.data == data)
            #expect(file.filename == "report.txt")
            #expect(file.contentType == "text/plain")
        } else {
            #expect(throws: AtlasAttachmentFile.Failure.self) { try AtlasAttachmentFile.read(url) }
        }
    }

    @Test func activityUsesAuthoritativeStatusAndKeepsReconnectSeparate() async throws {
        var sequence = 0
        var status: String?
        var liveMessage: String?
        var messages: [[String: Any]] = []
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            sequence += 1
            return try snapshot(sequence: sequence, selected: true, messages: messages, agentStatus: status, liveMessage: liveMessage)
        }, localRequest: { _ in throw CancellationError() })
        let cases: [(String?, String?)] = [
            ("queued", "Pip is getting ready…"), ("running", "Typing…"), ("compacting", "Compacting context…"),
            ("idle", nil), ("unknown", nil), (nil, nil)
        ]
        for (value, expected) in cases {
            status = value
            await model.load()
            #expect(model.activityMessage == expected)
        }
        messages = [[
            "id": "lookup", "kind": "tool", "body": "", "author_name": "Pip", "inserted_at": "2026-10-24T12:00:00Z",
            "tool_name": "get_account", "tool_status": "running", "tool_input": "", "tool_output": ""
        ], [
            "id": "finished", "kind": "tool", "body": "", "author_name": "Pip", "inserted_at": "2026-10-24T12:00:01Z",
            "tool_name": "get_tasks", "tool_status": "succeeded", "tool_input": "", "tool_output": ""
        ]]
        status = "running"
        await model.load()
        #expect(model.activityMessage == "Using get account…")
        #expect(model.timeline.groups.first?.messages.map(\.toolStatus) == ["running", "succeeded"])
        status = "compacting"
        await model.load()
        #expect(model.activityMessage == "Compacting context…")
        status = "idle"
        await model.load()
        #expect(model.activityMessage == nil)
        status = "running"
        messages[0]["tool_status"] = "succeeded"
        await model.load()
        #expect(model.activityMessage == "Typing…")
        #expect(model.timeline.groups.first?.messages.map(\.toolStatus) == ["succeeded", "succeeded"])
        liveMessage = "Reconnecting…"
        await model.load()
        #expect(model.liveMessage == "Reconnecting…")
        #expect(model.activityMessage == nil)
    }

    @Test func sendWaitsForDraftBridgeAndDoesNotReimplementIdempotency() async throws {
        var commands: [String] = []
        var draftSaved = false
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            let command = try #require(action["command"] as? [String: Any])
            let name = try #require(command["action"] as? String)
            commands.append(name)
            if name == "send" {
                #expect(draftSaved)
                #expect(command["address_agent"] as? Bool == true)
                #expect(command["id"] as? String == id)
                #expect(command["body"] as? String == "A thought")
                #expect(command["client_id"] == nil)
            }
            return try snapshot(sequence: name == "send" ? 3 : 1, selected: true)
        }, localRequest: { action in
            if action["action"] as? String == "close" { return Data("{}".utf8) }
            #expect(action["action"] as? String == "draft")
            #expect(action["id"] as? String == id)
            #expect(action["body"] as? String == "A thought")
            draftSaved = true
            return try snapshot(sequence: 2, selected: true, draft: "A thought")
        })
        _ = await model.privateThread()
        model.draft = "A thought"
        await model.send(addressAgent: true)
        #expect(commands == ["private", "send"])
        #expect(model.draft.isEmpty)
    }

    @Test func serverFailureKeepsTheFeatureAvailableForRetry() async {
        var fail = true
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"local-handle\"}".utf8) }
            if fail { throw AtlasAuthenticationError(kind: "server", message: "Try again later.") }
            return try snapshot(sequence: 1)
        }, localRequest: { _ in throw CancellationError() })
        await model.load()
        #expect(model.errorMessage == "Try again later.")
        fail = false
        await model.load()
        #expect(model.errorMessage == nil)
        #expect(model.assistant?.name == "Pip")
    }

    @Test func cardActionForwardsToRustAndRejectsLateEffectsAfterAccessLoss() async throws {
        var revoked = false
        var sequence = 0
        var delayed = false
        var pending: CheckedContinuation<Data, Error>?
        let message: [String: Any] = [
            "id": "evidence", "kind": "tool", "body": "", "author_name": "Pip", "inserted_at": "2026-10-22T12:00:00Z",
            "tool_status": "succeeded", "tool_input": "", "tool_output": "original evidence",
            "component": ["type": "result_table", "version": 1, "data": ["title": "Accounts", "columns": ["Name"], "rows": [["Northstar"]]],
                          "actions": [["id": "show_evidence", "label": "View source"]], "fallback": "Northstar"]
        ]
        let effect = Data("{\"effect\":\"show_evidence\",\"thread_id\":\"\(id)\",\"message_id\":\"evidence\"}".utf8)
        let model = AtlasOrbit(request: { action in
            if action["action"] as? String == "open" { return Data("{\"connection\":\"handle\"}".utf8) }
            sequence += 1
            return try snapshot(sequence: sequence, selected: !revoked, messages: revoked ? [] : [message])
        }, localRequest: { action in
            if action["action"] as? String == "close" { return Data("{}".utf8) }
            #expect(action["action"] as? String == "component_action")
            #expect(action["connection"] as? String == "handle")
            #expect(action["id"] as? String == id)
            #expect(action["message_id"] as? String == "evidence")
            #expect(action["event"] as? String == "show_evidence")
            if delayed { return try await withCheckedThrowingContinuation { pending = $0 } }
            return effect
        })
        await model.load()
        #expect(model.messages.first?.component?.data.rows == [["Northstar"]])
        #expect(await model.componentAction(messageId: "evidence", event: "show_evidence"))
        delayed = true
        let action = Task { await model.componentAction(messageId: "evidence", event: "show_evidence") }
        while pending == nil { await Task.yield() }
        revoked = true
        await model.load()
        pending?.resume(returning: effect)
        #expect(await action.value == false)
        #expect(model.messages.isEmpty)
        #expect(model.timeline.groups.isEmpty)
    }
}

extension AtlasOrbitTests {
    private func snapshot(
        sequence: Int, selected: Bool = false, draft: String = "", messages: [[String: Any]] = [],
        agentStatus: String? = nil, liveMessage: String? = nil, updatedAt: String = "2027-06-07T10:00:00Z",
        fields: [String: Any] = [:]
    ) throws -> Data {
        let thread: [String: Any] = [
            "id": id, "title": "Private thread", "kind": "private", "status": "idle",
            "summary": "", "origin": "manual", "participants": [], "updated_at": updatedAt,
            "agent_status": agentStatus as Any? ?? NSNull()
        ]
        let value: [String: Any] = [
            "sequence": sequence, "assistant": ["name": "Pip", "configured": true],
            "threads": [thread], "selected": selected ? thread as Any : NSNull(),
            "messages": messages, "people": [], "draft": draft, "loading": false, "history_loading": false, "saving": false,
            "has_more": true, "has_older": false, "needs_session": false, "live_message": liveMessage as Any? ?? NSNull()
        ]
        return try JSONSerialization.data(withJSONObject: value.merging(fields) { _, latest in latest })
    }
}
