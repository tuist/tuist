import ActivityKit
import SwiftUI
import WidgetKit

struct AtlasActivityMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 17, weight: .medium)).foregroundStyle(.mint)
            .accessibilityLabel("Pip")
    }
}

struct AtlasActivityView: View {
    let attributes: AtlasActivityAttributes
    let state: AtlasActivityAttributes.ContentState
    var stale = false
    var ended = false
    var island = false
    @Environment(\.dynamicTypeSize) private var textSize

    private var visible: [AtlasActivityAttributes.Conversation] {
        Array(state.conversations.prefix(textSize.isAccessibilitySize ? 1 : 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: island ? 4 : 8) {
            header
            if ended {
                Text("All caught up").font(.headline)
            } else {
                if stale {
                    Label("Updates unavailable · Open Atlas", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
                conversations
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, island ? 10 : 16)
        .padding(.vertical, island ? 4 : 12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            AtlasActivityMark().accessibilityHidden(true)
            Text("Pip").font(.caption.weight(.medium))
            if state.activeCount > 1, !ended {
                Text("\(state.activeCount) active").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if island, state.activeCount > visible.count, !ended {
                overflow
            } else if !stale, !ended, let start = state.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing).frame(maxWidth: 65)
                    .accessibilityLabel("Elapsed time")
            }
        }
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: island ? 4 : 8) {
            ForEach(visible) { conversation in
                if let destination = attributes.destination(for: conversation) {
                    Link(destination: destination) {
                        AtlasActivityConversation(conversation: conversation,
                                                  prominent: state.activeCount == 1, stale: stale)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !island, state.activeCount > visible.count {
                overflow
            }
        }
    }

    private var overflow: some View {
        Text("+\(state.activeCount - visible.count) more in Orbit")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

struct AtlasActivityConversation: View {
    let conversation: AtlasActivityAttributes.Conversation
    let prominent: Bool
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 6 : 2) {
            Text(conversation.displayTitle)
                .font(prominent ? .headline : .subheadline.weight(.medium))
                .lineLimit(prominent ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitive()
            if !stale {
                Label(conversation.status.label, systemImage: conversation.status.symbol)
                    .font(prominent ? .caption : .caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
