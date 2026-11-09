#if os(iOS)
    import SwiftUI
    import TuistServer

    extension JamConversationView {
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
                        let result = try await client.archive(id: jam.id, archived: value)
                        guard lifecycle == fence, !Task.isCancelled else { return }
                        jam = jam.mergingHistory(result)
                        update(jam)
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
                let before = older ? jam.nextBefore : nil
                let value = try await client.jam(id: jam.id, before: before)
                guard !Task.isCancelled, historyID == id else { return }
                jam = jam.mergingHistory(value, older: older)
                archived = jam.archiveStatus == "archived" || jam.status == "archived"
                update(jam)
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
                let preview = try await client.shipPreview(id: jam.id)
                guard !Task.isCancelled, lifecycle == fence, showingDiff else { return }
                shipPreview = preview
                error = nil
            } catch {
                guard !Task.isCancelled, lifecycle == fence, showingDiff else { return }
                self.error = error.localizedDescription
            }
        }

        func ship(_ preview: JamShipPreview) async {
            guard let client, !busy else { return }
            let fence = lifecycle
            busy = true
            defer { busy = false }
            do {
                let result = try await client.ship(id: jam.id, approval: preview)
                guard lifecycle == fence, !Task.isCancelled else { return }
                jam = jam.mergingHistory(result)
                update(jam)
                showingDiff = false
                shipPreview = nil
                error = nil
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }

        func send(shareConfirmed: Bool = false) async {
            guard !busy, !jam.isRunning, jam.status != "outcome_unknown",
                  !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !isLive, jam.visibility == "private", !draft.people.isEmpty, !shareConfirmed {
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
                    let value = try await client.send(submittedText, jamID: jam.id, requestID: requestID)
                    guard lifecycle == fence, !Task.isCancelled else { return }
                    jam = jam.mergingHistory(value)
                } else {
                    #if DEBUG
                        if shareConfirmed { jam.visibility = "shared" }
                        jam.messages.append(.init(id: UUID().uuidString, role: "user", content: submittedText))
                        jam.messages.append(.init(
                            id: UUID().uuidString,
                            role: "system",
                            content: "Preview only. No message or invitation was sent, no work ran, and no pull request was opened."
                        ))
                        jam.status = "preview"
                    #endif
                }
                if draft.text == submittedText { draft = JamConversationDraft() }
                requestID = UUID()
                update(jam)
                error = nil
                jump(to: "bottom")
            } catch {
                guard lifecycle == fence, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
#endif
