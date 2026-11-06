#if os(iOS)
    import SwiftUI
    import TuistServer
    import UIKit

    extension ThreadConversationView {
        var timeline: [[ThreadMessage]] {
            var groups: [[ThreadMessage]] = []
            for message in session.messages {
                if message.role == "tool", groups.last?.first?.role == "tool" {
                    groups[groups.count - 1].append(message)
                } else { groups.append([message]) }
            }
            return groups
        }

        @ViewBuilder
        func messageView(_ message: ThreadMessage) -> some View {
            if message.role == "system" {
                Text(message.content).font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.role == "assistant" ? "Tuist" : message.role == "user" ? "You" : message.role)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if message.role == "assistant" {
                        ThreadConversationRichContent(message: message).id(message)
                    } else {
                        ThreadConversationMarkdown(source: message.content).equatable()
                    }
                }
                .padding(message.role == "user" ? 14 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if message.role == "user" {
                        Color.clear.modifier(ThreadGlassSurface(cornerRadius: 22))
                    }
                }
                .contextMenu {
                    Button("Copy message", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content }
                }
            }
        }

        func toolGroup(_ messages: [ThreadMessage]) -> some View {
            DisclosureGroup {
                ForEach(messages) { message in
                    DisclosureGroup {
                        if let input = message.toolInput {
                            Text(input).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        ThreadConversationRichContent(message: message).id(message)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.toolName ?? "Tool result")
                            if let status = message.toolStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(.leading, messages.contains { $0.id == message.parentMessageID } ? 16 : 0)
                }
            } label: {
                Label("\(messages.count) tool \(messages.count == 1 ? "action" : "actions")", systemImage: "terminal")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .tint(.secondary)
            .accessibilityIdentifier("tool-evidence")
        }

        var composer: some View {
            VStack(spacing: 8) {
                if archived {
                    Button { setArchived(false) } label: {
                        Label("Restore thread", systemImage: "archivebox")
                            .padding(.horizontal, 20).frame(minHeight: 48)
                            .contentShape(Capsule())
                            .modifier(ThreadGlassSurface(cornerRadius: 28, interactive: true))
                    }.buttonStyle(.plain)
                } else {
                    if !isLive, let query = mentionQuery {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(["Tuist", "Marek", "Matic"].filter {
                                    query.isEmpty || $0.lowercased().hasPrefix(query.lowercased())
                                }, id: \.self) { name in
                                    Button { selectMention(name) } label: {
                                        Label(name, systemImage: name == "Tuist" ? "sparkles" : "person.crop.circle")
                                            .font(.subheadline).foregroundStyle(.primary)
                                            .padding(.horizontal, 16)
                                            .frame(minHeight: 44)
                                            .contentShape(Capsule())
                                            .modifier(ThreadGlassSurface(cornerRadius: 24, interactive: true))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                        }.scrollClipDisabled()
                    } else if draft.text.isEmpty, !busy, !session.suggestedPrompts.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(session.suggestedPrompts, id: \.self) { prompt in
                                    Button {
                                        draft.text = prompt
                                        composing = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.turn.up.right")
                                                .foregroundStyle(.tint).accessibilityHidden(true)
                                            Text(prompt).foregroundStyle(.primary)
                                                .frame(maxWidth: typeSize.isAccessibilitySize ? 240 : nil, alignment: .leading)
                                                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 44)
                                        .contentShape(Capsule())
                                        .modifier(ThreadGlassSurface(cornerRadius: 28, interactive: true))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(prompt)
                                    .accessibilityHint("Adds this suggestion to your draft without sending.")
                                }
                            }.padding(.horizontal, 16).padding(.vertical, 6)
                        }.scrollIndicators(.hidden).scrollClipDisabled()
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        let placeholder = typeSize.isAccessibilitySize ? "Message…" :
                            session.visibility == "shared" ? "Message, or ask @Tuist…" : "Message Tuist…"
                        TextField(
                            placeholder,
                            text: $draft.text,
                            prompt: Text(placeholder).foregroundStyle(.primary),
                            axis: .vertical
                        )
                        .lineLimit(1 ... 5).focused($composing)
                        .padding(.leading, 16).padding(.vertical, 12)
                        .padding(.trailing, 8)
                        .frame(minHeight: 52)
                        .modifier(ThreadGlassSurface(cornerRadius: 28))
                        .accessibilityIdentifier("thread-message")
                        if composing {
                            Button { composing = false } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 20))
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                                    .modifier(ThreadGlassSurface(cornerRadius: 24, interactive: true))
                            }
                            .foregroundStyle(.primary).buttonStyle(.plain)
                            .accessibilityLabel("Hide keyboard")
                        }
                        Button { Task { await send() } } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .semibold)).frame(width: 48, height: 48)
                                .contentShape(Circle())
                                .modifier(ThreadGlassSurface(cornerRadius: 24, interactive: true))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Send")
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy ||
                            session.isRunning || session.status == "outcome_unknown")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }

        private var mentionQuery: String? {
            guard let token = draft.text.split(whereSeparator: \.isWhitespace).last,
                  !draft.text.hasSuffix(" "), token.hasPrefix("@"), token.count <= 40 else { return nil }
            return String(token.dropFirst())
        }

        private func selectMention(_ name: String) {
            guard let query = mentionQuery else { return }
            draft.text = String(draft.text.dropLast(query.count + 1)) + "@\(name) "
            if name != "Tuist" { draft.people.insert(name) }
            composing = true
        }
    }
#endif
