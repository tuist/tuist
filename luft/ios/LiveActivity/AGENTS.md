# Threads Live Activity

The server owns what the activity shows: `ContentState` in `LuftActivityAttributes.swift`
mirrors the document `Tuist.Push.LiveActivities` builds (`server/lib/tuist/push/live_activities.ex`).
Change both together and bump the document's `v` for changes an older widget can't draw;
the widget shows `fallback` for versions past `supportedVersion`. Keep decoding lenient.

- The extension draws only. No networking, credentials, Keychain or core calls.
- Phases, symbols, tints and headlines come from the document; don't derive them in Swift.
  Unknown symbols and tints fall back rather than fail.
- The document carries thread titles and tool-derived phases only, never tool arguments,
  message text or results.
- Links open the app only through `luft://app/…`; `url(for:)` rejects anything else.
- `LuftActivityAttributes.swift` is compiled into both the app and the extension; keep it
  free of WidgetKit and app-only code.
- Validate on macOS with `mise run build:ios`.
