#if os(iOS)
    import SwiftUI
    import TuistServer

    extension ThreadConversationView {
        var details: some View {
            NavigationStack {
                Form {
                    Section("Goal") { Text(thread.goal) }
                    Section {
                        LabeledContent("AI provider") {
                            Text(verbatim: thread.provider.map {
                                ThreadModel(provider: $0, id: "", name: "").providerName
                            } ?? String(localized: "Not recorded"))
                        }
                        LabeledContent("Model") {
                            Text(verbatim: thread.model ?? String(localized: "Not recorded"))
                                .textSelection(.enabled)
                        }
                    } header: {
                        Text("AI model")
                    } footer: {
                        Text("The provider and model are fixed for this thread. Start a new thread to choose another model.")
                    }
                    Section {
                        LabeledContent("Repository", value: thread.repository)
                        LabeledContent("Worktree branch", value: thread.branch)
                        LabeledContent("Tool provider", value: "Tuist")
                        LabeledContent("Profile", value: thread.profile == "macos" ? "macOS" : "Linux")
                    } footer: {
                        Text(
                            "The server owns the thread; only tools run in the environment. Repository threads have their own worktrees."
                        )
                    }
                    Section("People") {
                        Label(
                            thread.visibility == "shared" ? "Shared conversation" : "Only you",
                            systemImage: thread.visibility == "shared" ? "person.2" : "lock"
                        )
                        Text(LocalizedStringKey(isLive ? "Private threads only" :
                                "Mention someone in a message to invite them. Inviting shares the existing history. @Tuist asks the bot to act. Sample people only."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Thread details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDetails = false } } }
            }
        }

        var diffSheet: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !isLive { Text("Illustrative diff · Not a live repository change").foregroundStyle(.secondary) }
                        if let preview = shipPreview {
                            LabeledContent("Target branch", value: preview.targetBranch)
                            LabeledContent("Mode", value: preview.mode)
                            LabeledContent("Base", value: preview.baseSHA)
                            LabeledContent("Head", value: preview.headSHA)
                            Text(verbatim: preview.diff).font(.caption.monospaced()).textSelection(.enabled)
                            Text("Shipping follows repository policy. Approving queues this exact reviewed change.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Approve and ship") { Task { await ship(preview) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy || !["direct", "branch"].contains(preview.mode))
                        } else {
                            Text(verbatim: thread.diff).font(.caption.monospaced()).textSelection(.enabled)
                            if loadingShipPreview { ProgressView() } else if !isLive {
                                Text("Design preview · Ship requires a live account and repository policy.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Button("Ship") {}.disabled(true)
                            }
                        }
                        if let error {
                            Text(verbatim: error).foregroundStyle(.red)
                            if isLive {
                                Button("Review again") { Task { await loadShipPreview() } }
                                    .disabled(busy || loadingShipPreview)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle("Changes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDiff = false } } }
                .task { await loadShipPreview() }
                .interactiveDismissDisabled(busy)
            }
        }

        var promptSheet: some View {
            NavigationStack {
                List {
                    ForEach(thread.messages.filter { !["assistant", "tool", "system"].contains($0.role) }) { message in
                        Button {
                            pendingJump = message.id
                            showingPrompts = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == "user" ? "You" : message.role).font(.caption).foregroundStyle(.secondary)
                                Text(message.content).lineLimit(3).foregroundStyle(.primary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Prompts").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPrompts = false } } }
            }
        }
    }
#endif
