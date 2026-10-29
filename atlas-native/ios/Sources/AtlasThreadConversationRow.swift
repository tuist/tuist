import SwiftUI

struct AtlasOrbitSearch: ViewModifier {
    @Binding var text: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "Search titles and summaries")
        } else {
            content
        }
    }
}

#if os(iOS)
struct AtlasMobileConversationRow: View {
    let thread: AtlasThread
    var domainTitle: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            if !thread.summary.isEmpty {
                Text(thread.summary).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            HStack(spacing: 8) {
                if let priority = thread.priorityTitle {
                    Text(priority).font(.caption.weight(.medium))
                        .foregroundStyle(thread.priority == "now" ? Color.accentColor : Color.secondary)
                }
                if let domainTitle { AtlasThreadDomainBadge(title: domainTitle) }
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize { timestamp }
                AtlasThreadRunningIndicator(running: thread.activityLabel != nil)
            }
            if typeSize.isAccessibilitySize { timestamp }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(([thread.kind == "private" ? "Private conversation" : "Shared conversation"]
                             + [thread.activityLabel].compactMap { $0 }).joined(separator: ". "))
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

struct AtlasThreadRunningIndicator: View {
    let running: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(.tint)
            .symbolEffect(.pulse, options: .repeating, isActive: running && !reduceMotion && scenePhase == .active)
            .opacity(running ? 1 : 0)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

struct AtlasThreadDomainBadge: View {
    let title: String

    var body: some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.quaternary, lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct AtlasOrbitDomainFilter: View {
    @ObservedObject var model: AtlasOrbit

    private var title: String {
        model.domainFilter == "unclassified" ? "Unclassified" : model.domainTitle(model.domainFilter) ?? "All domains"
    }

    var body: some View {
        Menu {
            Picker("Domain", selection: Binding(get: { model.domainFilter }, set: { domain in
                Task { await model.load(domain: domain) }
            })) {
                Text("All domains").tag("")
                ForEach(model.domains) { domain in Text(domain.name).tag(domain.id) }
                Text("Unclassified").tag("unclassified")
            }
        } label: {
            Label(model.domainFilter.isEmpty ? "Filter" : title,
                  systemImage: model.domainFilter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .disabled(model.assistant?.searchable != true || model.cached)
        .accessibilityLabel("Filter conversations")
        .accessibilityValue(title)
        .accessibilityIdentifier("orbit-filter")
    }
}
