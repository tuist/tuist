import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LuftLiveActivityBundle: WidgetBundle {
    var body: some Widget { LuftLiveActivityWidget() }
}

struct LuftLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LuftActivityAttributes.self) { context in
            LuftActivityView(attributes: context.attributes, state: context.state, stale: context.isStale)
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
                    LuftActivityIcon(symbol: symbol, tint: tint, size: 32)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(lead?.headline ?? context.state.summary.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LuftActivityProgress(progress: lead?.progress, stale: context.isStale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LuftActivityIslandDetail(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: LuftActivityStyle.symbol(symbol))
                    .foregroundStyle(LuftActivityStyle.color(tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(lead?.detail ?? context.state.summary.phase)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                        .accessibilityLabel("Updates paused")
                } else if context.state.threads.count > 1 {
                    Text("\(context.state.threads.count)")
                        .monospacedDigit()
                        .foregroundStyle(LuftActivityStyle.color(tint))
                        .contentTransition(.numericText(value: Double(context.state.threads.count)))
                        .accessibilityLabel(context.state.summary.headline)
                } else {
                    LuftActivityProgress(progress: lead?.progress, stale: false)
                        .frame(maxWidth: 44)
                        .foregroundStyle(LuftActivityStyle.color(tint))
                }
            } minimal: {
                Image(systemName: LuftActivityStyle.symbol(symbol))
                    .foregroundStyle(LuftActivityStyle.color(tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(context.state.summary.headline)
            }
            .widgetURL(lead.flatMap { context.attributes.url(for: $0) } ?? context.attributes.threadsURL)
            .keylineTint(LuftActivityStyle.color(tint))
        }
    }
}
