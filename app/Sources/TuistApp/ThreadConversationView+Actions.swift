#if os(iOS)
    import SwiftUI
    import TuistServer

    extension ThreadConversationView {
        func jump(to id: String) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrollID = id }
        }

        func setArchived(_ value: Bool) {
            guard !busy else { return }
            Task {
                let fence = lifecycle
                busy = true
                defer { busy = false }
                do {
                    if let client {
                        let result = try await client.archive(id: thread.id, archived: value)
                        guard lifecycle == fence, !Task.isCancelled else { return }
                        thread = thread.mergingHistory(result)
                        update(thread)
                    }
                    archived = value
                    archive(value)
                } catch { if lifecycle == fence { self.error = error.localizedDescription } }
            }
        }

        func refresh(older: Bool = false) async {
            guard let client else { return }
            if older, loadingHistory { return }
            let id = UUID()
            historyID = id
            loadingHistory = true
            defer { if historyID == id { loadingHistory = false } }
            do {
                let before = older ? thread.nextBefore : nil
                let value = try await client.thread(id: thread.id, before: before)
                guard !Task.isCancelled, historyID == id else { return }
                thread = thread.mergingHistory(value, older: older)
                archived = thread.archiveStatus == "archived" || thread.status == "archived"
                update(thread)
                error = nil
            } catch {
                guard !Task.isCancelled, historyID == id else { return }
                self.error = error.localizedDescription
            }
        }

        func loadShipPreview() async {
            guard let client, !loadingShipPreview else { return }
            let fence = lifecycle
            loadingShipPreview = true
            shipPreview = nil
            defer { loadingShipPreview = false }
            do {
                let preview = try await client.shipPreview(id: thread.id)
                guard !Task.isCancelled, lifecycle == fence, showingDiff else { return }
                shipPreview = preview
                error = nil
            } catch {
                guard !Task.isCancelled, lifecycle == fence, showingDiff else { return }
                self.error = error.localizedDescription
            }
        }

        func ship(_ preview: ThreadShipPreview) async {
            guard let client, !busy else { return }
            let fence = lifecycle
            busy = true
            defer { busy = false }
            do {
                let result = try await client.ship(id: thread.id, approval: preview)
                guard lifecycle == fence, !Task.isCancelled else { return }
                thread = thread.mergingHistory(result)
                update(thread)
                showingDiff = false
                shipPreview = nil
                error = nil
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }

        func send(shareConfirmed: Bool = false) async {
            guard !busy, !voice.isRecording, !thread.isRunning, thread.status != "outcome_unknown",
                  !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !isLive, thread.visibility == "private", !draft.people.isEmpty, !shareConfirmed {
                confirmingShare = true
                return
            }
            busy = true
            defer { busy = false }
            let fence = lifecycle
            let submittedText = draft.text
            if requestContent != submittedText {
                requestID = UUID()
                requestContent = submittedText
            }
            do {
                if let client {
                    let value = try await client.send(submittedText, threadID: thread.id, requestID: requestID)
                    guard lifecycle == fence, !Task.isCancelled else { return }
                    thread = thread.mergingHistory(value)
                } else {
                    #if DEBUG
                        if shareConfirmed { thread.visibility = "shared" }
                        thread.messages.append(.init(id: UUID().uuidString, role: "user", content: submittedText))
                        thread.messages.append(.init(
                            id: UUID().uuidString,
                            role: "system",
                            content: "Preview only. No message or invitation was sent, no work ran, and no pull request was opened."
                        ))
                        thread.status = "preview"
                    #endif
                }
                if draft.text == submittedText { draft = ThreadConversationDraft() }
                requestID = UUID()
                update(thread)
                error = nil
                jump(to: "bottom")
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
#endif
