import SwiftUI

struct AtlasThreadMessageView: View {
    let message: AtlasThreadMessage
    let selfId: String?
    var openAttachment: ((AtlasThreadAttachment) -> Void)?
    let action: (String) async -> Bool
    @State private var showingEvidence = false
    @State private var expandedEvidence = false
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var outgoing: Bool { message.kind == "human" && selfId != nil && message.authorId == selfId }
    private var palette: AtlasTheme.Palette? { contrast == .increased ? nil : theme?.palette(scheme) }
    private var fill: Color {
        if outgoing { return palette.map { Color(atlasHex: $0.accent) } ?? AtlasSettingsStyle.tint }
        return palette.map { Color(atlasHex: $0.surface) } ?? Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        Group {
            if message.kind == "system" {
                Text(message.body).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    if outgoing { Spacer(minLength: 40) }
                    VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                        if !outgoing, message.kind != "tool" {
                            Text(message.authorName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                        if message.kind == "tool" {
                            tool.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            messageBody.padding(.horizontal, 16).padding(.vertical, 12)
                                .foregroundStyle(outgoing
                                    ? palette.map { Color(atlasHex: $0.onAccent) } ?? AtlasSettingsStyle.onTint : .primary)
                                .background(fill, in: RoundedRectangle(cornerRadius: 20))
                        }
                        if let date = ISO8601DateFormatter().date(from: message.insertedAt) {
                            Text(date, style: .time).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12)
                        }
                    }
                    if !outgoing { Spacer(minLength: 40) }
                }
            }
        }
        .accessibilityIdentifier("thread-message-\(message.id)")
    }

    private var messageBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.body.isEmpty {
                if message.kind == "agent" {
                    AtlasMarkdown(source: message.body)
                } else {
                    Text(message.body).textSelection(.enabled)
                }
            }
            ForEach(message.attachments ?? []) { attachment in
                AtlasAttachmentChip(attachment: attachment, open: { openAttachment?(attachment) })
                    .disabled(openAttachment == nil)
            }
        }
    }

    private var tool: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let card = message.component, card.type == "account_card" { cardView(card) }
            toolEvidence
        }
    }

    private func cardView(_ card: AtlasThreadComponent) -> some View {
        AtlasThreadCardView(card: card) { event in
            Task {
                if await action(event) { showingEvidence = true; expandedEvidence = true }
            }
        }
    }

    private var toolEvidence: some View {
        DisclosureGroup(isExpanded: $expandedEvidence) {
            VStack(alignment: .leading, spacing: 8) {
                if let card = message.component, card.type != "account_card" { cardView(card) }
                if message.component == nil || message.component?.type == "account_card" || showingEvidence {
                    if !message.toolInput.isEmpty {
                        Text("Inputs").font(.caption.bold())
                        Text(message.toolInput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !message.toolOutput.isEmpty {
                        Text("Result").font(.caption.bold())
                        Text(message.toolOutput).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if !message.body.isEmpty { Text(message.body).font(.callout).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } label: {
            Label("\(message.toolName ?? "Tool") · \(message.toolStatus ?? "Working")", systemImage: "wrench.and.screwdriver")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .multilineTextAlignment(.leading)
    }
}
