import SwiftUI

#if os(iOS)
struct AtlasMobileConversationRow: View {
    let thread: AtlasThread
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: thread.kind == "private" ? "lock.bubble" : "bubble.left.and.bubble.right")
                .font(.title3).foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if let priority = thread.priorityTitle {
                    HStack(alignment: .firstTextBaseline) {
                        Text(priority).font(.subheadline.weight(.medium))
                            .foregroundStyle(thread.priority == "now" ? Color.accentColor : Color.secondary)
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 8)
                            timestamp
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.title).font(.headline).foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    if thread.priorityTitle == nil, !typeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                        timestamp
                    }
                }
                if !thread.summary.isEmpty {
                    Text(thread.summary).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                }
                if ["queued", "running", "compacting"].contains(thread.agentStatus ?? "") {
                    Label("Pip is working", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                }
                if typeSize.isAccessibilitySize { timestamp }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(thread.kind == "private" ? "Private conversation" : "Shared conversation")
    }

    @ViewBuilder private var timestamp: some View {
        if let date = thread.updatedDate {
            Group {
                if Calendar.current.isDateInToday(date) {
                    Text(date, format: .dateTime.hour().minute())
                } else {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                }
            }
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
        }
    }
}
#endif
