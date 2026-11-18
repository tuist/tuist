import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Draws the server's document. Every word, phase, symbol and tint comes from
/// it; this file only decides layout and how changes between pushes animate.
enum LuftActivityStyle {
    /// The fixed palette the server's `tint` names. Unknown names stay neutral.
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "red": .red
        case "teal": .teal
        default: .gray
        }
    }

    /// An SF Symbol the server named, or a neutral one this OS doesn't have.
    static func symbol(_ name: String) -> String {
        UIImage(systemName: name) == nil ? "circle.dashed" : name
    }
}

struct LuftActivityIcon: View {
    let symbol: String
    let tint: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: LuftActivityStyle.symbol(symbol))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(LuftActivityStyle.color(tint))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(LuftActivityStyle.color(tint).opacity(0.22), in: Circle())
            .accessibilityHidden(true)
    }
}

struct LuftActivityProgress: View {
    let progress: LuftActivityAttributes.ContentState.Progress?
    let stale: Bool

    var body: some View {
        // A build's timer also carries `done` of `total` targets, which
        // widgets that predate it ignore and keep counting time.
        if let progress, progress.kind == "timer", let done = progress.done, let total = progress.total, total > 0, !stale {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(done)/\(total)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(done)))
                ProgressView(value: Double(min(done, total)), total: Double(total))
                    .frame(width: 48)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) of \(total) targets")
        } else if let progress, progress.kind == "timer", let start = progress.startedAt, !stale {
            Text(timerInterval: Date(timeIntervalSince1970: start)...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 56, alignment: .trailing)
                .accessibilityLabel("Elapsed time")
        } else if let progress, progress.kind == "steps", let done = progress.done {
            Text("\(done) \(done == 1 ? "step" : "steps")")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(done)))
        }
    }
}

struct LuftActivityTrail: View {
    let tints: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tints.enumerated()), id: \.offset) { index, tint in
                Circle()
                    .fill(LuftActivityStyle.color(tint))
                    .opacity(index == tints.count - 1 ? 1 : 0.45)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LuftActivityThreadRow: View {
    let thread: LuftActivityAttributes.ContentState.Thread
    let stale: Bool

    var body: some View {
        HStack(spacing: 10) {
            LuftActivityIcon(symbol: thread.symbol, tint: thread.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.headline)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
                Text(thread.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                LuftActivityProgress(progress: thread.progress, stale: stale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LuftActivityTrail(tints: thread.trail)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Lock Screen and banner presentation.
struct LuftActivityView: View {
    let attributes: LuftActivityAttributes
    let state: LuftActivityAttributes.ContentState
    let stale: Bool
    @Environment(\.dynamicTypeSize) private var textSize

    private var visible: [LuftActivityAttributes.ContentState.Thread] {
        Array(state.threads.prefix(textSize.isAccessibilitySize ? 1 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LuftActivityStyle.color(state.summary.tint))
                    .accessibilityHidden(true)
                Text(state.summary.headline)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                Text(state.summary.phase)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LuftActivityStyle.color(state.summary.tint))
                    .contentTransition(.interpolate)
            }
            if stale {
                Label("Updates paused. Open Luft.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !state.supported {
                Text(state.fallback).font(.subheadline).privacySensitive()
            } else {
                ForEach(visible) { thread in
                    row(thread)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func row(_ thread: LuftActivityAttributes.ContentState.Thread) -> some View {
        HStack(spacing: 8) {
            if let url = attributes.url(for: thread) {
                Link(destination: url) { LuftActivityThreadRow(thread: thread, stale: stale) }
                    .buttonStyle(.plain)
            } else {
                LuftActivityThreadRow(thread: thread, stale: stale)
            }
            if let snooze = attributes.snoozeURL(for: thread) {
                LuftActivitySnoozeLink(url: snooze)
            }
        }
    }
}

/// Opens Luft's snooze choices for a thread. The extension only draws, so
/// the app does the snoozing.
struct LuftActivitySnoozeLink: View {
    let url: URL
    var size: CGFloat = 30

    var body: some View {
        Link(destination: url) {
            Image(systemName: "moon.zzz")
                .font(.system(size: size * 0.45, weight: .semibold))
                .frame(width: size, height: size)
                .background(.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Snooze")
    }
}

/// The Dynamic Island's expanded presentation, below its leading and trailing regions.
struct LuftActivityIslandDetail: View {
    let attributes: LuftActivityAttributes
    let state: LuftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lead = state.threads.first, state.supported {
                Text(lead.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                HStack(spacing: 6) {
                    if let snooze = attributes.snoozeURL(for: lead) {
                        LuftActivitySnoozeLink(url: snooze, size: 24)
                    }
                    Text(state.summary.headline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 4)
                    ForEach(state.threads.dropFirst()) { thread in
                        LuftActivityIcon(symbol: thread.symbol, tint: thread.tint, size: 18)
                    }
                }
            } else {
                Text(state.fallback).font(.caption).privacySensitive()
            }
        }
    }
}
