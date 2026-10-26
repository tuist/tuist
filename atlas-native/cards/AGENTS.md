# Thread card renderer

The server is the source of truth. `Atlas.Orbit.Components` chooses the
card type/version, title, columns, rows, actions and fallback from an authorized,
durable tool message. The client never interprets tool output to invent cards,
advance a run, or persist its own thread state.

`App.tsx` is a bundled, reviewed NSH 0.2.0 rendering implementation, not server
code. It receives only Rust-validated `result_table` and `account_card` v1 payloads
and local appearance colors through `atlas.thread-card`. Account cards require the
exact Field/Value shape; only the server projects allowlisted fields from an
existing redacted `get_account` result. Both hosts pass selected-theme text,
secondary text, surface, border and tint tokens, with native high-contrast fallback. The bridge's only commands
are measured height and an action ID. Rust checks action IDs against the current
message and selected thread before a native view reveals existing source
evidence. Future mutations require a server-authorized, persisted action endpoint;
never implement them as local card behavior.

## Build

`assets/nsh` contains source JavaScript, app identity, an empty capability
manifest and the upstream Apache license. No bytecode, signed packages, source
maps, remote URLs or downloaded code ship in this slice. Run:

```sh
NSH_BIN=/path/to/nsh-0.2.0 bash cards/build.sh
python3 cards/verify.py
```

Commit the reviewed TSX and generated source/metadata together. `bundle.json`
records their SHA-256 hashes. Both mobile SDK targets verify them during builds,
without downloading the NSH compiler. Only renderer edits need the CLI. The
checksum-pinned SDK integrations live in `../modules/nsh.star`.

## Host boundaries

- iOS `AtlasThreadCardView.swift` and Android `AtlasThreadCardView.kt`
  embed the release runtime only; no dev-server or package loading API is used.
- Hosts explicitly grant `{}`, set 16 MB JS heap / 512-node / 250 ms event limits,
  pass no credentials or transport handles, and use disposable private storage.
  The reviewed renderer imports no storage, network, filesystem or process API.
- The NSH region measures its natural height inside the native transcript. Native
  code retains the composer, keyboard, navigation, tool expansion and source view.
  Text follows platform scaling, contrast and the validated appearance palette.
- Unsupported/malformed versions are discarded by Rust without losing original
  tool output. NSH load/runtime/size failures use the server's text fallback.
  Android API 26–27 retains text without instantiating the API-28 NSH runtime.
- iOS account cards are visible inline in the timeline; result tables remain inside expandable tool evidence. The source action reveals the existing evidence without refetching or running a tool.
- A runtime exists only while its card view exists. Remove its storage
  and destroy/detach the runtime when the view leaves. Do not retain user data in
  a JS VM across users, selected servers or access revocation.

Rust contract/action tests, server projection/access tests, Swift adapter tests,
iOS thread UI tests and the isolated Android card preview cover separate
boundaries. Preview screenshots prove rendering, not live inference or OAuth.
