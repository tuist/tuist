import Foundation
import NukeUI
import SwiftUI
import TuistNoora
import TuistServer

public struct PreviewRowView: View {
    public enum Style {
        case standard
        case compact
    }

    let preview: ServerPreview
    let style: Style
    let onSelect: () -> Void
    @State private var isPressed = false

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    public init(preview: ServerPreview, style: Style = .standard, onSelect: @escaping () -> Void) {
        self.preview = preview
        self.style = style
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Noora.Spacing.spacing6) {
                LazyImage(url: preview.iconURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image("PreviewIconPlaceholder")
                            .resizable()
                            .scaledToFit()
                    }
                }
                .cornerRadius(Noora.CornerRadius.medium)
                .frame(width: style == .compact ? 40 : 48, height: style == .compact ? 40 : 48)

                VStack(alignment: .leading, spacing: Noora.Spacing.spacing2) {
                    if style == .standard {
                        HStack(spacing: Noora.Spacing.spacing4) {
                            if let commitSHA = preview.gitCommitSHA {
                                HStack(spacing: Noora.Spacing.spacing1) {
                                    NooraIcon(.timelineEvent)
                                        .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                        .frame(width: 12, height: 12)
                                    Text(String(commitSHA.prefix(7)))
                                        .font(.caption2)
                                        .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                }
                            }

                            if let track = preview.track, !track.isEmpty {
                                HStack(spacing: Noora.Spacing.spacing1) {
                                    Image(systemName: "tag")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12, height: 12)
                                    Text(track)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                .accessibilityElement(children: .combine)
                            }

                            Spacer()
                        }
                    }

                    Text(preview.displayName ?? "App")
                        .font(style == .compact ? .subheadline.weight(.semibold) : .headline.weight(.medium))
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                        .lineLimit(1)

                    if let summary = preview.releaseNotesSummary {
                        Text(verbatim: summary)
                            .font(.caption)
                            .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    HStack(spacing: Noora.Spacing.spacing4) {
                        HStack(spacing: Noora.Spacing.spacing1) {
                            NooraIcon(.history)
                                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                .frame(width: 12, height: 12)
                            Text(relativeDateFormatter.localizedString(for: preview.insertedAt, relativeTo: Date()))
                                .font(.caption2)
                                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                        }

                        if let branch = preview.gitBranch {
                            HStack(spacing: Noora.Spacing.spacing1) {
                                NooraIcon(.gitBranch)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                    .frame(width: 12, height: 12)
                                Text(branch)
                                    .lineLimit(style == .compact ? 1 : nil)
                                    .font(.caption2)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if style == .standard {
                    PreviewRunButton(preview: preview)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, style == .compact ? Noora.Spacing.spacing6 : Noora.Spacing.spacing5)
            .padding(.vertical, Noora.Spacing.spacing5)

            NooraDivider()
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(style == .compact ? .isButton : [])
        .onTapGesture {
            onSelect()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { isPressing in
            isPressed = isPressing
        } perform: {}
        .listRowBackground(
            Rectangle()
                .fill(isPressed ? Color(UIColor.systemGray4) : Color.clear)
        )
    }
}
