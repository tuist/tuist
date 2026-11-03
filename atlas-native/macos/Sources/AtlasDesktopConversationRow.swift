import SwiftUI

struct AtlasDesktopConversationRow: View {
    let thread: AtlasThread

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    .help(thread.title)
                Spacer(minLength: 0)
                if let date = thread.updatedDate {
                    Group {
                        if Calendar.current.isDateInToday(date) {
                            Text(date, format: .dateTime.hour().minute())
                        } else {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                }
            }
            HStack(spacing: 6) {
                Label(thread.kind == "private" ? "Private" : "Shared",
                      systemImage: thread.kind == "private" ? "lock" : "person.2")
                    .fixedSize()
                if ["queued", "running", "compacting"].contains(thread.agentStatus ?? "") {
                    Spacer(minLength: 6)
                    Label("Working", systemImage: "sparkles").fixedSize()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !thread.summary.isEmpty {
                Text(thread.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}
