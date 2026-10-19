import AppKit
import SwiftUI
import TuistServer

struct DesktopPreviewActions {
    let preview: ServerPreview?
    let canRefresh: Bool
    let refresh: () -> Void
}

private struct DesktopPreviewActionsKey: FocusedValueKey {
    typealias Value = DesktopPreviewActions
}

extension FocusedValues {
    var desktopPreviewActions: DesktopPreviewActions? {
        get { self[DesktopPreviewActionsKey.self] }
        set { self[DesktopPreviewActionsKey.self] = newValue }
    }
}

public struct DesktopCommands: Commands {
    @FocusedValue(\.desktopPreviewActions) private var actions

    public init() {}

    public var body: some Commands {
        CommandMenu("Preview") {
            Button("Refresh Previews") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions?.canRefresh != true)
            Divider()
            if let preview = actions?.preview {
                ShareLink("Share Preview…", item: preview.url)
                Button("Copy Preview Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview.url.absoluteString, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Open in Browser") { NSWorkspace.shared.open(preview.url) }
                    .keyboardShortcut("o", modifiers: [.command, .option])
            } else {
                Button("Share Preview…") {}.disabled(true)
                Button("Copy Preview Link") {}.disabled(true)
                Button("Open in Browser") {}.disabled(true)
            }
        }
    }
}
