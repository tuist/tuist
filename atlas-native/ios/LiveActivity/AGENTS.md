# Pip Live Activity

`AtlasActivityAttributes` is the data-only ActivityKit wire contract shared by the
host app and WidgetKit extension. Use explicit snake-case CodingKeys: APNs decodes
content state with Apple's default JSON strategy. Unix seconds are numeric, not
Foundation's reference-date encoding. Optional conversation titles are an explicit
contextual exception: the server cleans and bounds them to 80 Unicode codepoints
after authorization, including every APNs send. Apple receives them and they can
appear on the Lock Screen. Missing titles from older servers use "Conversation".
Keep message excerpts, people, tool names, arguments, results and credentials out
of attributes and content state. Mark rendered titles privacy-sensitive so the
system can redact them.

The extension renders one aggregate activity with up to three conversations and
the total active count. One conversation leads with a two-line title and secondary
phase; multiple conversations use at most two titled rows (one at accessibility
text sizes) and an overflow count. Generic phases come from the authorized server
projection; elapsed time is not estimated percent completion. Do not crowd the
Island with tool counters, per-row arrows or decorative progress rings.
Keep the Island's overflow count in its header instead of a footer so both titled
rows and phases fit the system's expanded height. Lock Screen spacing is separate.
Show stale updates honestly and end when no work remains. Native timers and
system-controlled expansion replace continuously animated web UI. Conversation
links are hints reauthorized through the host's existing origin-bound router.

Keep `@main` outside host source globs. The extension has no networking, Rust auth,
Keychain or App Group access. Once's narrow `atlas_widget_extension` kind packages
the real `.appex`; the app embeds it before signing. Device distribution requires
an independently authorized extension profile, never the host's entitlements.
The separate preview target may render synthetic states, but must not enter
production source lists or claim APNs delivery from offline screenshots.
