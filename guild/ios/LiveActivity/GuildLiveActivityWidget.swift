import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GuildLiveActivityBundle: WidgetBundle {
    var body: some Widget { GuildLiveActivityWidget() }
}

struct GuildLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuildActivityAttributes.self) { context in
            GuildActivityView(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
                .widgetURL(context.attributes.threadsURL)
        } dynamicIsland: { context in
            let lead = context.state.supported ? context.state.threads.first : nil
            let symbol = lead?.symbol ?? context.state.summary.symbol
            let tint = lead?.tint ?? context.state.summary.tint
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GuildActivityIcon(symbol: symbol, tint: tint, size: 32)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(lead?.headline ?? context.state.summary.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GuildActivityProgress(progress: lead?.progress, stale: context.isStale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GuildActivityIslandDetail(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: GuildActivityStyle.symbol(symbol))
                    .foregroundStyle(GuildActivityStyle.color(tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(lead?.detail ?? context.state.summary.phase)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                        .accessibilityLabel("Updates paused")
                } else if context.state.threads.count > 1 {
                    Text("\(context.state.threads.count)")
                        .monospacedDigit()
                        .foregroundStyle(GuildActivityStyle.color(tint))
                        .contentTransition(.numericText(value: Double(context.state.threads.count)))
                        .accessibilityLabel(context.state.summary.headline)
                } else {
                    GuildActivityProgress(progress: lead?.progress, stale: false)
                        .frame(maxWidth: 44)
                        .foregroundStyle(GuildActivityStyle.color(tint))
                }
            } minimal: {
                Image(systemName: GuildActivityStyle.symbol(symbol))
                    .foregroundStyle(GuildActivityStyle.color(tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(context.state.summary.headline)
            }
            .widgetURL(lead.flatMap { context.attributes.url(for: $0) } ?? context.attributes.threadsURL)
            .keylineTint(GuildActivityStyle.color(tint))
        }
    }
}
