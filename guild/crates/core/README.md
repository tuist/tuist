# Mobile core contract

The Tuist Guild native clients use this crate; it does not migrate or replace the
shipping apps' credential stores. Keep its vault in a separate Tuist Guild secure
storage namespace. Never log host actions, HTTP authorization/body fields, or the
vault. Run calls on a background thread; they are synchronous and serialized for
the entire operation, including native callbacks. A callback must not reenter.

## Bridges

Apple uses `include/tuist_app.h`. `tuist_app_call(request_json, host, context)`
returns an owned NUL-terminated UTF-8 string, freed once with `tuist_app_free`.
The host's NUL-terminated response remains **host-owned** and valid until the next
host invocation. Rust copies it immediately; no host free callback is needed.
Inputs need only remain valid for the duration of their call.

Android exports `Java_dev_tuist_guild_AppCore_request`, implementing
`AppCore.private external fun request(input: String, host: AppHost): String`.
`AppHost` exposes `public fun perform(action: String): String`. Keep these names
and the callback method from obfuscation. JNI callback exceptions become sanitized
errors, not exception messages. The JNI dependency is Android-only for normal
builds, and also a test dependency to compile-check marshalling on Linux.

The theme catalog is `tuist_app_theme()` on Apple (static process-lifetime JSON;
never free it) and `AppCore.theme()` on Android
(`Java_dev_tuist_guild_AppCore_theme`). Both return `theme::json()`:
`{"default": "noora", "themes": [{"id", "name", "appearance": null | "light" | "dark",
"light": {"<token>": "#rrggbb", ...}, "dark": {...}}, ...]}`. Noora comes first and
follows the system (`appearance` null); Omarchy themes have one appearance, and
edges should force it on system chrome. Edges store only the chosen `id` and fall
back to `default` for an unknown one.

A thread's agent can restyle the app with the `set_theme` tool the live socket
offers (`live_connect`). Its schema lists every token with what it colors and
Noora's values; the core builds the theme from a base theme, an appearance
(required for Noora; an Omarchy base keeps its own and refuses the other) and
the colors it overrides, and `live_receive` hands it to the edge with ID
`custom`. Edges keep that one custom theme beside the catalog, select it at
once, and show it as **Custom** until the person picks another.

The tab catalog is `threads` (index 0, the default), `halls`, `dms`, then `profile`; its C/JNI symbols are unchanged. Edges label `dms` **DMs**.
Rust callers can instantiate `MobileClient` and implement `Host` independently. The hall operations live in `Halls`, behind the same `Transport`, with `organizations` for frontends that have no account menu. Presence lives in `Presence`, behind a `Socket` the caller implements. The thread operations live in `Threads`, behind a `Transport` that sends authorized JSON requests; GPUI calls it directly with its desktop session.

## Native host actions

| Action | Response |
| --- | --- |
| `{"type":"read"}` | `{"value":null}` or `{"value":"<opaque vault JSON>"}` |
| `{"type":"write","value":"<opaque vault JSON>"}` | `{"ok":true}` |
| `{"type":"http","method":"GET","url":"https://…","headers":{"Accept":"application/json",…},"body":"optional string"}` | `{"status":200,"body":"<response text>"}`; `{"error":"offline"}` only when the server is unreachable (no connection, DNS, connect failure, timeout), which makes thread operations answer from the local store. Any other error (TLS, size) stays an error |
| `{"type":"socket_open","url":"wss://…","protocols":["phoenix","base64url.bearer.phx.…"]}` | `{"ok":true}`; opens the presence WebSocket, replacing any open one, and starts buffering its text frames. The second protocol carries the access token: never log it |
| `{"type":"socket_send","text":"…"}` | `{"ok":true}`, or an error once closed |
| `{"type":"socket_read"}` | `{"frames":["…",…],"closed":false}`: the text frames received since the last read, without blocking, and whether the connection has closed |
| `{"type":"socket_close"}` | `{"ok":true}` |
| `{"type":"store_directory"}` | `{"path":"/absolute/directory"}` |
| `{"type":"log","message":"…"}` | `{"ok":true}`; any failure is ignored |

`store_directory` says where the local store lives (`src/store.rs`): one SQLite
database per profile (`{profile}.sqlite3`, plus WAL files), which the core
opens, migrates and queries itself so screens render before the network answers
and stay navigable offline. Hosts return a directory outside backups
(Application Support on Apple, `noBackupFilesDir` on Android). SQLite is
bundled, so every platform runs the same version; on `wasm32-unknown-unknown`
rusqlite uses `sqlite-wasm-rs`, and a browser host would return the path of an
OPFS-backed VFS (for example `sqlite-wasm-vfs`'s `sahpool`). The model stays in
Rust so every platform behaves the same.

The schema is `store::MIGRATIONS`, an append-only list: each entry runs once per
database in its own transaction, and `PRAGMA user_version` records how many
have. Add a migration for every schema change and never edit a shipped one;
keep `outbox` rows, which are writes the server hasn't seen. A database from a
newer build is refused. `log` carries the core's boot and migration messages to
the system log (`Logger` subsystem `dev.tuist.guild`, category `core`, on
Apple; tag `TuistGuild` on Android); they never contain tokens or server text.

Every action may instead return `{"error":"…"}`. The core deliberately does not
display that message. Write success means durable completion, not a queued write.
Read failures must be errors, never `value:null`. HTTP must use platform TLS,
forbid insecure HTTP except loopback, and forbid cross-origin redirects. No
credential-bearing request may be redirected to another origin. Native hosts
must enforce response size/time limits. The core does not follow redirects or
retry HTTP itself; transient failures preserve saved credentials for a later call.

## Operations

Requests are `{"operation":"…","args":{…}}`. No-argument operations may omit
`args`. Responses always have `view` and `data`, plus `error` on failure:

```json
{
  "view": {
    "profiles": [{"id":"opaque","server":"https://tuist.dev/","handle":"ana","email":"ana@example.com","organization":null,"organizations":[],"rejected":false}],
    "accounts": [{"profile_id":"opaque","name":"ana","server":"https://tuist.dev/","handle":"ana","personal":true,"rejected":false,"selected":true}],
    "active_profile_id":"opaque",
    "generation":1
  },
  "data":null
}
```

Tokens never belong in a view. Raw API data is retained except secret fields and
credential strings are scrubbed; errors are fixed, credential-free messages.
`rejected` also includes membership-access denial: do not offer these profiles
for organization selection. `accounts` flattens every profile's personal
account and cached organizations into one switcher list, sorted by name and
server. A membership shared by several profiles on the same server appears once,
owned by the active profile when it is one of them. Select a row with
`select_organization` and its `profile_id` and `name`; rows of rejected profiles
list only the personal account. Generation advances on durable profile/selection or
membership commits, not on token rotation. Always render the returned view even
when an operation reports an error.

| Operation | Args | Data |
| --- | --- | --- |
| `snapshot` | none | null |
| `routes` | none | `{routes:["/threads","/threads/{id}","/halls","/halls/{id}","/dms","/dms/{id}","/profile"]}`; the shared addressable screen catalog |
| `navigate` | `url`: internal path, `tuist-guild://app/…`, or HTTPS `{server}/guild/…`; optional `if_generation` and `if_revision` | null; updates navigation, or queues a signed-out link until sign-in; a mismatched version makes an async completion a no-op |
| `select_tab` | `tab`: `threads`, `halls`, `dms` or `profile` | null; each conversation tab keeps its own open conversation across tab changes |
| `navigation_back` | none | null; returns to the selected tab's list (Threads from Profile) |
| `boot` | none | `{stores:[{profile,migrated:[…]},…]}`. Call it first at launch: it migrates every profile's local store and logs each step; a store that fails to open is logged, left out of `stores`, and retried when used |
| `begin_sign_in` | `server`, optional `provider`: `tuist` (default), `github`, `google`, `apple` | `{url,callback_scheme:"tuist-guild"}`; the URL uses the Tuist Guild client (`tuist_oauth::GUILD_CLIENT_ID`) and requests no scope; it first reads `/.well-known/tuist.json` and fails with an update-the-server error unless `guild_oauth_client_id` names that client |
| `finish_sign_in` | `url` | null |
| `cancel_sign_in` | none | null |
| `switch_profile` | `id` | null |
| `select_organization` | profile `id`, `name` (null or account handle selects personal account) | null |
| `sign_out` | none | `{push_unregister_failed}`; unregisters the profile's push installation, best effort, then removes the active profile and selects the first eligible fallback. `push_unregister_failed` is true when the server couldn't be told, so the edge invalidates its device token |
| `organizations` | none | `[{id:<profile ID>,response:<raw organizations response>},…]` |
| `threads` | optional nonempty `cursor` | `{available,reason,freshness,threads:[{…,state,section},…],next_cursor}`. `threads` is the whole stored inbox with threads started offline first (`pending: true`), and `freshness.state` is `live`, or `cached` (with `as_of`) or `never_loaded` when the network is unreachable. `thread`, `start_thread` and `send_message` answer from the store the same way offline; the two writes queue and return the conversation with `freshness.state` `queued`. Results come from `/api/accounts/{account}/threads`, where the account is the selected organization or, when none is selected, the personal account (as are `start_thread`, `thread` and `send_message`); `state` is `queued`, `running` (also `compacting` and `shipping`), `completed` (the server's `idle`), `failed` (also `interrupted`), `outcome_unknown` or null for statuses the core doesn't know, and `section` is `in_progress`, `recent` or `archived`; a repeated cursor ends paging; a 404 returns `available:false`, `reason:"disabled"` and no threads, and a 401/403 (the session predates Guild's first-party client; signing in again uses it) returns `available:false`, `reason:"sign_in_required"`; neither replaces the stored inbox |
| `cached_threads` | none | the selected account's inbox from the local store, without the network, shaped like `threads` |
| `cached_thread` | `id` | a conversation from the local store, shaped like `thread` |
| `flush_outbox` | none | `{sent}`; sends writes queued offline in order with their original `request_id`, stops at the first failure that may clear up (offline, 5xx, a busy thread, credentials) and keeps the rest, and marks writes the server refuses (400, 404, 422) as `failed`. A queued `start_thread` that is sent moves its replies to the server's thread id; the local id keeps working as an alias for `thread`, `cached_thread` and `send_message` |
| `start_thread` | `content` (nonempty, at most 16,000 bytes) | the created thread, as `thread` returns it; starts a server-side conversation with no repository (its agent checks one out in the thread's workspace when the conversation needs it), using the first model from `/threads/models`. A 404 reports threads unavailable; no available model asks to connect a ChatGPT subscription. A retry of the same text after a failure reuses its `request_id`, so it never creates two threads |
| `thread` | thread `id` (UUID), optional `before` message position | the server's thread with its latest messages, plus `state`, `section` and `working` (queued or running, and not archived); frontends poll it while `working`. A message's optional `ui` is a card the model wrote: NSH JavaScript `source` and a `size` of `compact`, `medium` or `tall`, to which the core adds the frame `height` in points (120, 240, 400). Edges show the card at that height and its `content` when they can't run it; the core drops a `ui` with an unknown size or an empty or larger than 256 KiB source |
| `send_message` | thread `id`, `content` | the updated thread; retries reuse the request ID like `start_thread` |
| `live_wait` | `socket`: a handle the edge picks for one screen's live socket | `{delay_ms}`: how long to wait before the next `live_connect` of that socket. Call it before every attempt: it is 0 at first and after a connection that joined, and backs off to 30 s while attempts fail, whether to connect, to join, or after a socket that stopped answering |
| `live_connect` | `socket`, thread `id` (UUID) | `{url,protocols,join,tick_ms}`: how to open the live socket of the thread a screen shows. The edge opens a WebSocket to `url` with `protocols` (the bearer travels as Phoenix's `base64url.bearer.phx.` subprotocol, standard unpadded base64 as Phoenix decodes it, never in the URL), sends `join` first, then calls `live_tick` every `tick_ms`. The join offers the thread's agent the tools Guild exposes (`set_theme`); the core refreshes the access token first |
| `live_tick` | `socket` | `{send,reconnect}`: frames to send (the heartbeat), or `reconnect: true` to close the socket and start again with `live_wait`, because the server never answered the last heartbeat, as when a network change leaves the socket half open. The edge also closes the socket when a send fails |
| `live_receive` | `socket`, thread `id`, `message`: one text frame | `{refresh,reconnect,replies,theme}`: `refresh` asks the edge to load the thread again, `reconnect` to close the socket and start again, `replies` are frames to send back as they are, and `theme` is a custom theme to apply and select before sending them, in the theme catalog's shape with `id` `custom` (Profile lists it as **Custom**). A frame for another account's topic, after an account switch, reconnects, and a tool call on it is answered with an error at once |
| `live_close` | `socket` | null; forgets the socket once its screen is gone |
| `halls` | none | `{available,reason,halls:[…],directs:[…]}` from `/api/accounts/{account}/halls`. Halls are long-lived conversations between people, with no agent: `halls` are the organization's named halls by name, which every member reads and writes, and `directs` are the person's direct conversations (2 to 8 people) by latest activity. Each has `id`, `kind` (`hall` or `direct`), `title` (`#name`, or the other people's handles), `name`, `topic`, `members` (the other people, `[{id,handle,online}]`, directs only; `online` means they have Guild open in this organization), `last_position`, `read_position`, `unread`, `updated_at` and `last_message`. A personal account answers `available:false`, `reason:"personal"` without a request; a 404 (flags off or not a member) `reason:"disabled"`; a 401/403 `reason:"sign_in_required"`. Not stored offline yet |
| `hall` | `id`, optional `before` message position | the hall as `halls` describes it, plus its latest 50 `messages` (`{id,position,body,author:{id,handle,online},mine,inserted_at}`, oldest first), `has_more` and `next_before`. Frontends poll it every few seconds while it is visible |
| `send_hall_message` | `id`, `content` (nonempty, at most 16,000 bytes) | the updated hall; a retry of the same text after a failure reuses its `request_id` |
| `read_hall` | `id`, `position` | `{read_position}`; moves the person's read position forward (never back). Call it with `last_position` when a hall is shown |
| `create_hall` | `name`, optional `topic` (at most 250 characters) | the new hall. The name is lowercased, a leading `#` dropped and spaces become `-`; it then must be letters, digits, `-` or `_`, at most 64 characters. A taken name fails with "A hall with this name already exists" |
| `start_direct` | `user_ids`: one to seven people from `hall_people` | the direct conversation with them, created the first time; the same people always reach the same conversation |
| `hall_people` | none | `{people:[{id,handle,online}]}`: the organization's other members, to pick for `start_direct` |
| `presence` | none | `{available,reason,connected,online:[{id,handle}]}`. Keeps the person joined to the selected organization's presence (`presence:<organization>` on `/threads/socket`, Phoenix's channel protocol, over the `socket_*` host actions), so the organization sees them online, and returns who else is. Call it every few seconds while the app is in front, and `presence_disconnect` when it leaves: the person shows online only while it is called. It reconnects after drops (5 s) and refusals (60 s, `reason:"disabled"`), heartbeats every 25 s, and follows organization changes. A personal account answers `reason:"personal"` and opens nothing. While joined, `halls`, `hall` and `hall_people` responses get `online` from this live state instead of the server's answer |
| `presence_disconnect` | none | null; closes the presence connection, so the person shows offline. `sign_out` also closes it |
| `projects` | none | `{projects:[…]}`; complete enumeration, deduplicated and account-scoped |
| `previews` | `project`: `account/project`, optional nullable `track`, `search`, `page` (default 1), `page_size` (default 20, maximum 100) | raw previews response |
| `tracks` | `project` | raw full-project `{total_count,tracks:[{name,count}]}` |
| `preview` | `project`, preview `id` | raw preview response |
| `delete_preview` | `project`, preview `id` | null on 204 |
| `preview_update` | `platform`: `ios`, `macos` or `android`; `binary_id`: the running build's Mach-O UUID (Apple) or APK SHA-256 (Android) | `{update:null}` or `{update:{id,version,commit,inserted_at,release_notes,url,install_url}}`: the newest `internal`-track preview of `tuist/guild` on tuist.dev whose build for that platform has a binary ID, unless it is the running build. Uses the selected profile when it is on tuist.dev, otherwise the first tuist.dev profile; no tuist.dev profile, 401/403 and 404 all return `update:null`. `install_url` is the preview's `itms-services` manifest on iOS and the build download elsewhere |
| `push_register` | `platform`: `ios`, `macos` or `android`; `token`: the APNs (hex) or FCM token; `environment`: `sandbox` or `production` (Android: `production`); `installation_id`: a fresh lowercase UUID; optional `name`: the device model shown in the person's device list, such as `iPhone 17 Pro` | `{registered:true,registration_id}`; `{registered:false,reason:"disabled"}` without a request while the profile has notifications off; or `{registered:false,reason:"removed"}` once the person removed this device from their device list, which turns them off. Registers the device for the active profile at `/api/me/push-devices/{installation}`; the profile keeps its installation ID and moves to `installation_id` when the server retired the old one. The vault records it without a new generation. `sign_out` unregisters, best effort |
| `push_enable` | `enabled`: boolean | null; the active profile's notification choice on this device, exposed as profiles' `push_enabled` and kept across signing in to the profile again. Off by default. Turning it off unregisters the installation first and fails, leaving it on, if the server can't be told (a 404 counts as done) |
| `open_notification` | `url`: a server-scoped Guild URL; optional `account`: the handle of the account it belongs to; optional `user`: the handle of the person it's for | null; switches to the saved profile on that server signed in as `user` with the account (the active one first) and to the account, then navigates. Signed out, it waits for sign-in like `navigate`; an account no profile has is an error that changes nothing |
| `delete_account` | none | null; deletes personal account and removes active profile |

Project requests must match the selected organization, or personal account when
none is selected. The verified paths are `/api/projects`, `/api/organizations`,
`/api/projects/{account}/{project}/previews`, that path plus `/tracks` or
`/{id}`, and `/api/accounts/{personal_handle}` for account deletion. Self-hosted
base paths are retained. Project pagination is followed only when the server
advertises more pages; repeated/empty nonterminal pages are errors. The current
server returns all projects without pagination. Ignored track/search semantics
are rejected when returned rows do not match, never repaired into partial totals.
Track discovery does not derive choices/counts from downloaded previews. An older
server's missing discovery is an error for that operation; browsing still works.

Every view also contains `navigation: {tab,thread_id,hall_id,dm_id,path,revision}`. `thread_id`, `hall_id` (the Halls tab's open hall) and `dm_id` (the DMs tab's) are nullable and survive tab selection; `path` describes the visible destination. Revision is process-local and increases on navigation changes; ignore older view revisions within the same session generation. Edges bind native tab/stack controls to this state, send user actions back through the operations above, and fetch conversation data through `thread`, or `hall` for `hall_id` and `dm_id` (DMs use the same hall operations; navigation itself performs no network requests). See the workspace README's Deep links section for URL scoping, launch examples and reserved web URLs. Navigation is in memory only, never in the credential vault.

Sign-in uses the server's static Tuist Guild client, a public PKCE client, with
the distinct `tuist-guild://oauth-callback` redirect.
The exact callback authority/path, a unique state and code are required. Every
finish consumes its pending attempt, including malformed/tampered callbacks.
Cancel preserves the current selection. PKCE, authorization URL construction and
JWT identity/expiry parsing reuse the existing OAuth/JWT crates. Credentials are
deduplicated by normalized origin and JWT user identity, not email or username.

Token refresh starts 30 seconds before expiry at the profile's own `/oauth2/token`
with its issuing client ID. Transient failures retain the pair; invalid_grant,
401 and tokenless success mark the profile rejected. A rotated pair is retained
in memory even if secure storage fails. Every subsequent operation first retries
the pending durable write, and performs no other work until it succeeds. Native
storage failure must remain visible; restarting the process before a failed write
can be recovered cannot preserve memory-only credentials.

Earlier macOS builds used the Tuist app's Keychain session for some profiles.
Loading a vault from those builds drops them and writes the vault back, so those
users sign in to Tuist Guild once; the Tuist app's items are never touched.
