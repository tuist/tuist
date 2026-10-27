import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AtlasLiveActivityBundle: WidgetBundle {
    var body: some Widget { AtlasLiveActivityWidget() }
}

struct AtlasLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AtlasActivityAttributes.self) { context in
            AtlasActivityView(attributes: context.attributes, state: context.state,
                              stale: context.isStale, ended: context.state.isEmpty)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(.mint)
                .widgetURL(context.attributes.destination())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    AtlasActivityView(attributes: context.attributes, state: context.state,
                                      stale: context.isStale, ended: context.state.isEmpty, island: true)
                }
            } compactLeading: {
                AtlasActivityMark()
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "wifi.slash").foregroundStyle(.secondary).accessibilityLabel("Updates unavailable")
                } else if context.state.activeCount > 1 {
                    Text("\(context.state.activeCount)").monospacedDigit().foregroundStyle(.mint)
                        .accessibilityLabel("\(context.state.activeCount) active conversations")
                } else {
                    Image(systemName: context.state.conversations.first?.status.symbol ?? "checkmark")
                        .foregroundStyle(.mint)
                        .accessibilityLabel(context.state.conversations.first?.status.label ?? "Finished")
                }
            } minimal: {
                Image(systemName: context.isStale ? "wifi.slash" : "sparkle")
                    .foregroundStyle(context.isStale ? Color.secondary : .mint)
                    .accessibilityLabel(context.isStale ? "Pip updates unavailable" : "Pip is working")
            }
            .widgetURL(context.attributes.destination(
                for: context.state.activeCount == 1 ? context.state.conversations.first : nil
            ))
            .keylineTint(.mint)
        }
    }
}
