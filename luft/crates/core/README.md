# Mobile core contract

## Native release review

Profile → Releases → Release review uses the shell's existing native stack.
Release operations use the authenticated selected account and require `generation`
and a host-generated UUID `surface`. Detail operations also require the immutable
`hash`, never a list index, title or the current active-release alias.

| Operation | Behavior |
| --- | --- |
| `releases` | GET `/api/accounts/{account}/releases`; replaces list and clears detail authority |
| `release_open` | GET `/api/accounts/{account}/releases/{hash}`; validates and loads exact review |
| `release_approve` | POST that hash's `/approve` with `{}`, only for the loaded review's Rust-selected `approve` action |
| `release_merge` | POST that hash's `/merge` with `{}`, only for the loaded review's Rust-selected `merge` action; does not activate |
| `release_activate` | POST that hash's `/activate` with `{}`, only for the loaded review's Rust-selected `activate` action |
| `release_close` | Clears this generation/surface; a stale close cannot clear a newer surface |

The ordinary response's `data` is `{surface:{list,detail},error}`. `list` is null
or `{active,releases:[metadata]}`; `detail` is null or the validated API detail,
plus `actions:["approve"|"merge"|"activate"]`, `review_changes:[{path,kind,before,after}]`
(the before/after values are exact pretty-printed JSON strings), `definition_text`
and `baseline_text` (complete pretty-printed JSON). Swift adapts these values,
localizes stable state/kind/action IDs, and displays server blockers verbatim.
It does not infer permissions, author a summary, or execute candidate source.

The core validates metadata, identities, JSON pointers, before/after values and
coverage of all differing definition subtrees. It refuses a review that secret
scrubbing would alter. Approval requires a proposed candidate and excludes the author.
Merge requires `can_merge: true`, empty `merge_blockers`, and state `approved` or
`merging`. Missing merge fields remain readable but never grant merge authority.
`merging` means the uncertain merge awaits reconciliation; `merged` means merged
but not active; `merge_conflict` means main moved and a new proposal is needed.
Activation requires a merged, compatible, never-activated candidate without blockers. Server capability
booleans remain required and the server rechecks current grants, runtime and
baseline at POST time. Approval, merge and activation are separate deliberate actions.
After each successful POST the core GETs the list and the exact hash's detail;
any failed reload clears authority rather than showing a guessed success state.
Writes are online-only, never automatically replayed or queued offline. After an
uncertain outcome, reload and inspect current state before another deliberate action.
Every failed/stale request clears review authority. Profile/account generation
commits, `release_close`, and background `presence_disconnect` clear it as well.

GPUI calls the public `ReleaseReviews` state machine directly with its existing
authenticated `Session` transport; it does not synthesize a mobile profile or
duplicate release validation. Its authority binds the server, account, actor,
generation and surface. Deactivation invalidates queued transport work, clears
the review and confirmation, and requires a fresh list on return.

Each native edge presents approval separately from activation. Apple and Android
show a system activation dialog naming the exact hash and an explicit Cancel;
GPUI uses an inline confirmation with initial focus on Cancel, Escape to cancel,
and focus restored to the activation button. Back reloads the list rather than
restoring stale review authority. Android discards review data on pause and
restores only an open-route flag after Activity recreation, never a pending write.

## Authenticated session records

A thread message may contain `record_reference: {model,id}`. It is a persisted
locator, not a snapshot, grant, URL or executable card. Native hosts open its
message ID, not a record inferred from conversation text. The iOS conversation
pushes a record destination and preserves native Back to the session. The installed
module can then navigate to a linked customer within its own native stack.

`record_*` operations use the ordinary authenticated client and session view.
Every call requires `thread`, `message`, `generation` (the current session view's
generation) and `surface` (a host-generated UUID unique to the mounted destination).
Changing account/profile invalidates the surface; a stale close cannot dismiss a
newer instance of the same reference. These operations never use a preview token
or the offline outbox.

- `record_open`: GET the message's authorized catalog/entry, then fetch the canonical
  record. Returns `{view,data,error?,entry}` inside the ordinary response's `data`.
  Here the nested view is the workspace view with `preview:false`.
- `record_refresh`: also takes `model,id`; re-fetches through the selected module's getter.
- `record_query`: also takes `query,input`.
- `record_action`: also takes `action,input,request_id`; the host supplies a fresh UUID
  for a deliberate submission, while the core retains it for retry.
- `record_retry`: repeats the retained submission without accepting a new identity.
- `record_close`: clears this surface's source, data and authority. An unresolved
  submission remains in memory for reopening the same reference in this session.

Rust uses only the active Luft origin and account, refreshes its normal credentials
and binds data requests to `/api/accounts/:account/threads/:thread/records/:message`.
The server independently rechecks current membership, thread access, configured
organization/database binding, user grants and declared module capabilities on
every request, including replay. HTTP 401/403 clears the runtime's source, rows and
pending submission. Access changes are detected on requests, not by a background
subscription. Reopening refreshes both grants and record state.

Background/foreground and transport recovery preserve the exact unresolved request
for the same generation/thread/message, without retaining a data or permission
snapshot. A fresh authorized open is required before replay. Revocation, switching
to another reference/account, or process termination discards that in-memory
identity; inspect current state before deliberately submitting again in those cases.

Installed UI receives data, its filtered capabilities and an initial `entry`, never
credentials. `entry` lets a module mount its record page instead of its list.
Generated cards retain their separate reply-only bridge. Server installation/grants
are opt-in administrative configuration; this does not provision databases or
implement a hosted app directory or row-level policy language. See the Luft server
README for the exact binding and grant configuration.

## Explicit local workspace connection

The `workspace_*` operations are an isolated, in-memory API through the same
`MobileClient::call`/C bridge. They bypass identity boot and never read/write the
credential vault or production session. Other callers may also own a standalone
`workspace::Workspace`. Apple exposes this only in its simulator opt-in root;
see [the local workspace example](../../workspaces/customer-management/README.md).

Requests use the usual `{operation,args}` shape. Responses have
`{view:{preview:true,connected,title,modules,selected,items,record,warning,can_retry},data,error?}`;
this is **not** a session view. Each module includes its validated published source.
No URL/token is returned. Error strings are fixed, never server/host text.

| Operation | Args | Behavior |
| --- | --- | --- |
| `workspace_connect` | `url`, `token` | Drops the old connection, validates an explicit origin (root loopback HTTP or HTTPS, no user info/query/fragment), gets `/workspace`, selects its first module |
| `workspace_snapshot` | none | Returns current in-memory workspace view without HTTP |
| `workspace_select` | `module` | Validates selection against the manifest, clears list/pending action |
| `workspace_open` | `module`, `model`, `id` UUID | Opens a typed reference to the selected module's model through its explicitly declared getter; fetches every time, validates identity, retains canonical `record` separately from the bounded list |
| `workspace_query` | `module`, `query`, `input` | List takes `{}` and validates at most 100 ID-sorted rows. Get takes exactly `{id:UUID}` and validates `{record}` including its requested identity, without replacing the selected list |
| `workspace_action` | `module`, `action`, `request_id` UUID, `input` | Validates capability/values and update ID/revision, calls `/action`, validates saved record, then refreshes the module's list if declared. A committed write remains successful with `warning` if that read fails |
| `workspace_retry` | `module` | Repeats the pending action with identical serialized body/request ID; never creates a new submission |
| `workspace_disconnect` | none | Clears source, records, pending action and credentials; subsequent calls fail without HTTP until explicit reconnect |

The caller supplies a fresh UUID for a deliberate submission (Apple uses the OS
UUID service). Safe automatic transport retry and deliberate retry reuse the
stored request, not a renderer-provided ID. Only HTTP host actions are used;
the HTTP host must retain the redirect/TLS/time/size restrictions below. A
detected sustained transport failure or 401 disconnects and clears everything.
Malformed responses do not enter state. Stored definitions support positive model
versions and string/enum/UUID-reference fields; create inputs may omit defaulted fields and
optional response fields may be null. String bounds are 4,000 UTF-8 bytes.

A module can declare a cross-model getter only for a reference target in its own
model. That getter still requires an explicit capability; a reference alone
grants nothing. Cross-model writes are rejected. After writes the core refreshes
the selected model's list, never whichever query happens to be first. Native host
events update a running module without recreating its page history or drafts;
module selection and disconnect dispose it. These preview capabilities do not
replace actor-level server authorization, which is not part of this local pilot.

A pending submission blocks fresh writes until the caller retries the retained
request or explicitly leaves the module/disconnects. A failed read cannot discard
that identity. Successful writes update the canonical open record before refreshing
the list. Contextual record entry therefore does not depend on the record appearing
in the first 100 list rows, and reopening never treats transcript text as current data.

The Luft native clients use this crate and default to `https://luft.work`; it does not migrate or replace the
shipping apps' credential stores. Custom origins must be Luft servers advertising the fixed native client through `/.well-known/luft.json`. Keep its vault in a separate Luft secure
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

A thread's agent can share its plan with the server's `update_progress` tool.
The plan arrives as a message whose `progress` holds its `steps` (`title`,
`status`: `pending`, `in_progress` or `completed`). `thread` adds `completed`,
`total` and `active` (the run showing it still works) to each plan, drops a plan
it can't show so edges render the message's `content` checklist, and sets the
conversation's `activity` to `{"title","step","total"}` (the active plan's
current step) or null. Edges show `activity` in place of a generic working label.

An open thread's optional `workspace_ready_id` identifies its current ready
sandbox residency, not merely a working agent. The server supplies it only when
the current run owns a running sandbox and its repository checkout is ready.
The core clears it for cached/offline history and ended runs. iOS presents one
brief edge glow per residency, a static cue with Reduced Motion, and a ready
label; no readiness cue is inferred from agent status alone.

Tool messages returned by `thread` include `toolResult`: `text` unwraps up to four
all-text MCP envelopes and formats JSON; `preview` contains its first 1,200
characters; `raw` formats the original JSON without unwrapping it. Malformed
text and mixed text/image/resource results remain readable without dropping
non-text evidence. A recognized `test_cases` list also provides `testCases`
(`name`, optional `module`, `suite`, `flaky`, `state`) for native cards, in the
returned order, not ranked by flakiness. Apple shows three cards initially,
with Show more/less, and a separate scrollable raw result. Sharing/copying
uses the unchanged message `content`, not the derived preview. Launch the
iOS simulator with `-LuftToolPreview` for a signed-out presentation fixture.

A decision is an assistant message with `decision: {question: string,
options: [{id: string, label: string}], allow_other: bool,
status: "pending" | "answered" | "cancelled", answer?: {option_id: string | null,
text: string} | null}`. The core preserves this metadata in live and cached
conversations. A pending decision may also have a `medium` `ui` (height 240);
terminal decisions have no UI source. Apple grants only pending decision cards
the `answer` host capability, accepts only an ID from that message's options,
and supplies its label to `answer_question`. Generic cards have only `reply`,
which edits the composer and never submits. Native fallbacks retain option and
dismiss actions; terminal decisions render the question and recorded result.

Conversations also expose `suggestions`: up to three follow-up drafts from the
latest assistant message, only after the run completes and while not archived.
The core omits blank, non-string and over-120-codepoint values, and clears the
list after a new prompt, including one queued offline. Cached conversations use
the same rule. Native edges show these above an empty reply field; choosing one
fills and focuses the composer, never sends it or replaces an existing draft.
These arrive in the server's final-answer data, not as tool calls.
`suggestion_icons` maps those draft texts to optional semantic IDs: `investigate`,
`test`, `explain`, or `retry`. The core drops unknown IDs and icons for drafts
that aren't shown, including on cached reads. Apple renders SF Symbols, Android
renders bundled Google Material outlined icons (license: `android/MATERIAL_ICONS_LICENSE`),
and GPUI renders Lucide. Missing icons stay text-only; platform symbol names
never cross the bridge. The server preserves its string-valued `suggestions`
array for older clients and stores the optional icon metadata separately.

The tab catalog is `threads` (index 0, the default), `lounges`, `dms`, `profile`, then `ops` (index 4); its C/JNI symbols are unchanged. Edges label `dms` **DMs** and `ops` **Ops**, which holds Collections and Releases.
Rust callers can instantiate `MobileClient` and implement `Host` independently. The lounge operations live in `Lounges`, behind the same `Transport`, with `organizations` for frontends that have no account menu. Presence lives in `Presence`, behind a `Socket` the caller implements. The thread operations live in `Threads`, behind a `Transport` that sends authorized JSON requests; GPUI calls it directly with its desktop session. AI subscriptions live in `ai_subscriptions::call` and MCP servers in `mcp_servers::call`, behind the same `Transport`.

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
Apple; tag `Luft` on Android); they never contain tokens or server text.

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
    "profiles": [{"id":"opaque","server":"https://luft.work/","handle":"ana","email":"ana@example.com","organization":null,"organizations":[],"rejected":false}],
    "accounts": [{"profile_id":"opaque","name":"ana","server":"https://luft.work/","handle":"ana","personal":true,"rejected":false,"selected":true}],
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
| `routes` | none | `{routes:["/threads","/threads/new","/threads/new/dictation","/threads/{id}","/threads/{id}/snooze","/lounges","/lounges/{id}","/dms","/dms/{id}","/profile","/ops"]}`; the shared addressable screen catalog |
| `navigate` | `url`: internal path, `luft://app/…`, or HTTPS `{server}/luft/…`; optional `if_generation` and `if_revision` | null; updates navigation, or queues a signed-out link until sign-in; a mismatched version makes an async completion a no-op |
| `select_tab` | `tab`: `threads`, `lounges`, `dms`, `profile` or `ops` | null; each conversation tab keeps its own open conversation across tab changes |
| `navigation_back` | none | null; returns to the selected tab's list (Threads from Profile) |
| `boot` | none | `{stores:[{profile,migrated:[…]},…]}`. Call it first at launch: it migrates every profile's local store and logs each step; a store that fails to open is logged, left out of `stores`, and retried when used |
| `begin_sign_in` | `server`, optional `provider`: `tuist` (default), `github`, `google`, `apple` | `{url,callback_scheme:"luft"}`; the URL uses the Luft client (`tuist_oauth::LUFT_CLIENT_ID`) and requests no scope; it first reads `/.well-known/luft.json` and fails unless `luft_oauth_client_id` names that fixed client. Authorization uses the Luft server's `/oauth2/authorize`, `/oauth2/github`, `/oauth2/google` or `/oauth2/apple` |
| `finish_sign_in` | `url` | null |
| `cancel_sign_in` | none | null |
| `switch_profile` | `id` | null |
| `select_organization` | profile `id`, `name` (null or account handle selects personal account) | null |
| `sign_out` | none | `{push_unregister_failed}`; unregisters the profile's push installation, best effort, then removes the active profile and selects the first eligible fallback. `push_unregister_failed` is true when the server couldn't be told, so the edge invalidates its device token |
| `organizations` | none | `[{id:<profile ID>,response:<raw organizations response>},…]` |
| `threads` | optional nonempty `cursor` | `{available,reason,freshness,threads:[{…,state,section},…],next_cursor}`. `threads` is the whole stored inbox with threads started offline first (`pending: true`), and `freshness.state` is `live`, or `cached` (with `as_of`) or `never_loaded` when the network is unreachable. `thread`, `start_thread` and `send_message` answer from the store the same way offline; the two writes queue and return the conversation with `freshness.state` `queued`. Results come from `/api/accounts/{account}/threads`, where the account is the selected organization or, when none is selected, the personal account (as are `start_thread`, `thread` and `send_message`); `state` is `queued`, `running` (also `compacting` and `shipping`), `completed` (the server's `idle`), `failed` (also `interrupted`), `outcome_unknown` or null for statuses the core doesn't know, and `section` is `in_progress`, `recent` or `archived`; a repeated cursor ends paging; a first page without a cursor keeps the threads loaded after it and returns the stored `next_cursor` that continues after them (a thread that changed moves into the first page), unless the first page is the whole inbox, which replaces it; a 404 returns `available:false`, `reason:"disabled"` and no threads, and a 401/403 returns `available:false`, `reason:"sign_in_required"` (sign in again for expired/rejected credentials or newly required upstream scopes); neither replaces the stored inbox |
| `cached_threads` | none | the selected account's inbox from the local store, without the network, shaped like `threads` |
| `cached_thread` | `id` | a conversation from the local store, shaped like `thread`, with `freshness.state` `live` while its live socket keeps it in sync. A reply queued offline shows at the end with `send_state` `offline`, or `failed` once the server refused it, until the server's copy arrives (matched by `request_id`) |
| `flush_outbox` | none | `{sent}`; sends writes queued offline in order with their original `request_id`, stops at the first failure that may clear up (offline, 5xx, a busy thread, credentials) and keeps the rest, and marks writes the server refuses (400, 404, 422) as `failed`. A queued `start_thread` that is sent moves its replies to the server's thread id; the local id keeps working as an alias for `thread`, `cached_thread` and `send_message` |
| `start_thread` | `content` (at most 16,000 bytes), optional `attachments`, optional `runner_id` | the created thread, as `thread` returns it; starts a server-side conversation with no repository (its agent checks one out in the thread's workspace when the conversation needs it), or on the runner when `runner_id` is set (the server's 409 `runner_offline` reports the runner offline; with no network it fails rather than queueing), using the first model from `/threads/models`. A 404 reports threads unavailable; no available model asks to connect a ChatGPT subscription in Profile. A retry of the same text and attachments after a failure reuses its `request_id`, so it never creates two threads |
| `ai_subscriptions` | none | `{subscriptions:[{provider,connected,updated_at,login_available,runs_threads},…]}` from `/api/me/ai-subscriptions`, which the Luft server keeps. `provider` is `claude` or `chatgpt` (open: show unknown ones by name); `runs_threads` says whether threads can run on it (only ChatGPT: Claude refuses third-party use of its subscriptions). A 404 is "not available for this account". Keep it live with `live_connect` and `id` `ai_subscriptions` |
| `connect_claude` | `token`: what `claude setup-token` prints (trimmed) | the updated list; a token the server refuses fails with a message asking for the setup token. The token never enters a view, the vault or the store |
| `start_chatgpt_login` | none | `{login_id,user_code,verification_url,interval,expires_at}`: an OpenAI device sign-in. Show the code and the URL, then poll |
| `poll_chatgpt_login` | `login_id` | `{status}`: `pending`, `connected`, or `failed` once it expired or OpenAI refused it. Poll no faster than `interval` |
| `cancel_chatgpt_login` | `login_id` | null; a sign-in the server already forgot counts as cancelled |
| `disconnect_ai_subscription` | `provider`: `claude` or `chatgpt` | the updated list |
| `mcp_servers` | optional `account_handle` | `{servers:[{id,name,url,connected,updated_at},…]}`: the person's own MCP servers from `/api/me/mcp-servers`, offered in every thread they write in, or with `account_handle` the organization's from `/api/accounts/{account_handle}/mcp-servers`, offered in its threads. Every member sees an organization's servers; only admins change them, and a 403 says so. A 404 is "not available for this account" |
| `add_mcp_server` | `url` (HTTPS), optional `name`, optional `account_handle` | `{server}`, not signed in yet; adding a URL again returns the existing server. Refusals name the problem (URL, name, at most 25 servers) |
| `remove_mcp_server` | `id`, optional `account_handle` | null; removes the server and the session Luft holds for it |
| `authorize_mcp_server` | `id`, optional `account_handle` | `{url,callback_scheme}`: open `url` in the browser like a sign-in; the server's authorization server returns to Luft, which hands the answer to `luft://mcp-callback`. The core remembers the profile and list until `complete_mcp_server` |
| `complete_mcp_server` | `url`: the `luft://mcp-callback` URL | `{server}`, connected. A sign-in completes once and only in the profile that started it; a cancelled one fails with "The sign-in was cancelled." without a request |
| `runners` | none | `{runners:[{id,name,platform,online,capabilities,last_seen_at},…]}` from `/api/me/thread-runners` |
| `register_runner` | `name`, `platform` | the runner plus its one-time encrypted `luft_runner_…` token, bound to the Luft session, and the profile's Luft `server`, for `luft-runner connect`; the raw upstream runner secret never reaches the client |
| `remove_runner` | runner `id` | null; revokes it on the server |
| `thread` | thread `id` (UUID), optional `before` message position | the server's thread with its latest messages, plus `state`, `section` and `working` (queued or running, and not archived); frontends poll it while `working`. A message's optional `ui` is a card the model wrote: NSH JavaScript `source` and a `size` of `compact`, `medium` or `tall`, to which the core adds the frame `height` in points (120, 240, 400). Edges show the card at that height and its `content` when they can't run it; the core drops a `ui` with an unknown size or an empty or larger than 256 KiB source |
| `send_message` | thread `id`, `content`, optional `attachments` | the updated thread; retries reuse the request ID like `start_thread`. With a pending decision, the server treats text as its answer (free text only when `allow_other`, otherwise an exact option label/ID), preserving any attachments |
| `answer_question` | thread `id`, message `question_id` (UUID), `content` (chosen label or localized dismissal text), either `option_id` or `cancel:true`; optional UUID `request_id` | the updated thread from the existing messages endpoint, saved to the conversation store. Online only: never enqueues a structured answer or optimistically changes a decision offline. Retries of the same question/option/content reuse the request ID; different questions/options are distinct writes |
| `snooze_thread` | thread `id`; `snooze`: `until_needed`, a future UTC RFC 3339 time, or null to wake it | the updated thread. A snoozed thread has `section` `snoozed` and `snooze: {until, until_needed}` (null otherwise) in `threads`, `thread` and their cached forms, until `until` passes or, for `until_needed`, its run stops; sending it a message wakes it. The server holds back the thread's finished notification while a timed snooze lasts, reminds the person when it ends, and leaves snoozed threads out of the Live Activity. `until_needed` on a thread that already finished fails with an error that says so. Needs the network; it isn't queued offline |
| `archive_thread` | thread `id`; optional `archived` (default true; false restores it) | the updated thread, with `section` `archived`, or back in its inbox section when restored; archiving stops its run if it was working. Needs the network; it isn't queued offline |
| `reauthorize_thread` | thread `id`, `consent:true` from an explicit owner action | the updated thread, persisted in the store. Online only, never queued or automatically called after sign-in or a failed message. Posts to `/threads/{id}/reauthorize` with current credentials; the server rechecks fresh scope, ownership and idle state. Consent authorizes future turns only, never resumes historical queued work or sends a draft |
| `snooze_options` | `offset_seconds`: the device's UTC offset now; optional `working` | `{options:[{id,until},…]}`: what Snooze offers, in order, for the edge to label: `until_needed` (only while `working`, `until` null), `in_1_hour`, `in_2_hours`, `in_4_hours`, `this_evening` (18:00 local, offered before 17:00), `tomorrow` and `next_week` (09:00 local, next Monday). Pass `until` to `snooze_thread`; a custom time is any later time the edge picks |
| `live_wait` | `socket`: a handle the edge picks for one screen's live socket | `{delay_ms}`: how long to wait before the next `live_connect` of that socket. Call it before every attempt: it is 0 at first and after a connection that joined, and backs off to 30 s while attempts fail, whether to connect, to join, or after a socket that stopped answering |
| `live_connect` | `socket`, thread `id` (UUID), or `inbox` | `{url,protocols,join,tick_ms,refresh_ms}`: how to open the live socket of the thread a screen shows, or with `inbox` of the threads list, which the server pushes to when any of the person's threads in the account changes (so the list reloads `threads`), or with `ai_subscriptions` of the person's AI subscriptions, which the server pushes to when one connects or disconnects, from Luft or anywhere else (so the screen reloads `ai_subscriptions`; its topic names no account, so it survives account switches). `refresh_ms` is the least time between two refreshes the edge runs for this socket: refreshes asked for meanwhile fold into one that follows, and run beside the socket rather than holding up its frames. It is 2000 for the inbox, which hears every thread while agents work, and 0 for a thread. The edge opens a WebSocket to `url` with `protocols` (the bearer travels as Phoenix's `base64url.bearer.phx.` subprotocol, standard unpadded base64 as Phoenix decodes it, never in the URL), sends `join` first, then calls `live_tick` every `tick_ms`. The join offers the thread's agent the tools Luft exposes (`set_theme`); the core refreshes the access token first. A thread's socket joins in sync mode from the revision the local store has: the server pushes `diff`s of the rows that changed since, which `live_receive` stores |
| `live_tick` | `socket` | `{send,reconnect}`: frames to send (the heartbeat), or `reconnect: true` to close the socket and start again with `live_wait`, because the server never answered the last heartbeat, as when a network change leaves the socket half open. The edge also closes the socket when a send fails |
| `live_receive` | `socket`, thread `id` (or `inbox`), `message`: one text frame | `{refresh,reconnect,replies,theme}`: `refresh` asks the edge to load the thread (or the inbox) again, `reconnect` to close the socket and start again, `replies` are frames to send back as they are, and `theme` is a custom theme to apply and select before sending them, in the theme catalog's shape with `id` `custom` (Profile lists it as **Custom**). A frame for another account's topic, after an account switch, reconnects, and a tool call on it is answered with an error at once. A thread's `diff` never reaches the edge: the core merges it into the local store and answers `changed: true`, and the edge reads the conversation again with `cached_thread` instead of loading it |
| `live_close` | `socket` | null; forgets the socket once its screen is gone |
| `lounges` | none | `{available,reason,lounges:[…],directs:[…]}` from `/api/accounts/{account}/lounges`. Lounges are long-lived conversations between people, with no agent: `lounges` are the organization's named lounges by name, which every member reads and writes, and `directs` are the person's direct conversations (2 to 8 people) by latest activity. Each has `id`, `kind` (`lounge` or `direct`), `title` (`#name`, or the other people's handles), `name`, `topic`, `members` (the other people, `[{id,handle,online}]`, directs only; `online` means they have Luft open in this organization), `last_position`, `read_position`, `unread`, `updated_at` and `last_message`. A personal account answers `available:false`, `reason:"personal"` without a request; a 404 (flags off or not a member) `reason:"disabled"`; a 401/403 `reason:"sign_in_required"`. Not stored offline yet |
| `lounge` | `id`, optional `before` message position | the lounge as `lounges` describes it, plus its latest 50 `messages` (`{id,position,body,author:{id,handle,online},mine,inserted_at}`, oldest first), `has_more` and `next_before`. Frontends poll it every few seconds while it is visible |
| `send_lounge_message` | `id`, `content` (nonempty, at most 16,000 bytes) | the updated lounge; a retry of the same text after a failure reuses its `request_id` |
| `read_lounge` | `id`, `position` | `{read_position}`; moves the person's read position forward (never back). Call it with `last_position` when a lounge is shown |
| `create_lounge` | `name`, optional `topic` (at most 250 characters) | the new lounge. The name is lowercased, a leading `#` dropped and spaces become `-`; it then must be letters, digits, `-` or `_`, at most 64 characters. A taken name fails with "A lounge with this name already exists" |
| `start_direct` | `user_ids`: one to seven people from `lounge_people` | the direct conversation with them, created the first time; the same people always reach the same conversation |
| `lounge_people` | none | `{people:[{id,handle,online}]}`: the organization's other members, to pick for `start_direct` |
| `palette` | `query`; optional `labels`: the edge's localized titles by destination ID and `new_conversation` | `{items:[{kind,id,title,url,…},…]}`: what ⌘K offers, best match first, at most 20. `kind` is `destination`, `action` (New conversation), `thread`, `lounge` or `dm`, and `url` is the route to pass to `navigate`. An empty query lists the destinations, New conversation and the five latest threads; otherwise every word must appear in the title, ranked exact, prefix, word prefix, then substring. It reads the stored inbox and the lounges `lounges` last returned for this account, without the network, so edges call it on every keystroke |
| `presence` | none | `{available,reason,connected,online:[{id,handle}]}`. Keeps the person joined to the selected organization's presence (`presence:<organization>` on `/threads/socket`, Phoenix's channel protocol, over the `socket_*` host actions), so the organization sees them online, and returns who else is. Call it every few seconds while the app is in front, and `presence_disconnect` when it leaves: the person shows online only while it is called. It reconnects after drops (5 s) and refusals (60 s, `reason:"disabled"`), heartbeats every 25 s, and follows organization changes. A personal account answers `reason:"personal"` and opens nothing. While joined, `lounges`, `lounge` and `lounge_people` responses get `online` from this live state instead of the server's answer |
| `presence_disconnect` | none | null; closes the presence connection, so the person shows offline. `sign_out` also closes it |
| `projects` | none | `{projects:[…]}`; complete enumeration, deduplicated and account-scoped |
| `previews` | `project`: `account/project`, optional nullable `track`, `search`, `page` (default 1), `page_size` (default 20, maximum 100) | raw previews response |
| `tracks` | `project` | raw full-project `{total_count,tracks:[{name,count}]}` |
| `preview` | `project`, preview `id` | raw preview response |
| `delete_preview` | `project`, preview `id` | null on 204 |
| `preview_update` | `platform`: `ios`, `macos` or `android`; `binary_id`: the running build's Mach-O UUID (Apple) or APK SHA-256 (Android) | `{update:null,suggest:false}` or `{update:{id,version,commit,inserted_at,release_notes,url,install_url},suggest}`: the newest `internal`-track preview of `tuist/luft` through `https://luft.work` whose build for that platform has a binary ID, unless it is the running build. Uses the selected profile when it is on luft.work, otherwise the first luft.work profile; no luft.work profile, 401/403 and 404 all return `update:null`. `install_url` is the preview's `itms-services` manifest on iOS and the build download elsewhere. `suggest` is true the first time this process reports a build, so edges ask once per launch to update now |
| `push_register` | `platform`: `ios`, `macos` or `android`; `token`: the APNs (hex) or FCM token; `environment`: `sandbox` or `production` (Android: `production`); `installation_id`: a fresh lowercase UUID; optional `name`: the device model shown in the person's device list, such as `iPhone 17 Pro` | `{registered:true,registration_id}`; `{registered:false,reason:"disabled"}` without a request while the profile has notifications off; or `{registered:false,reason:"removed"}` once the person removed this device from their device list, which turns them off. Registers the device for the active profile at `/api/me/push-devices/{installation}`; the profile keeps its installation ID and moves to `installation_id` when the server retired the old one. The vault records it without a new generation. `sign_out` unregisters, best effort |
| `push_enable` | `enabled`: boolean | null; the active profile's notification choice on this device, exposed as profiles' `push_enabled` and kept across signing in to the profile again. Off by default. Turning it off unregisters the installation first and fails, leaving it on, if the server can't be told (a 404 counts as done) |
| `live_activity_register` | `id`: the lowercase UUID the edge gave the threads Live Activity it started; `token`: its ActivityKit push token (hex); `environment`: `sandbox` or `production` | `{registered:true}`; `{registered:false,reason:"retired"}` when the server retired that ID (end the activity, start another with a new ID); or `{registered:false,reason:"unavailable"}` on a server without Live Activities (404). Registers at `/api/me/thread-live-activities/{id}` for the active profile; the server then pushes the activity's whole content, a versioned document the widget only draws. Refreshing the same ID is idempotent |
| `live_activity_unregister` | `id`; optional `profile_id`: the profile that registered it (default: the active one) | `{unregistered}`, best effort; a 404 counts as done. The server also retires registrations when the sign-in ends or after eight hours |
| `live_activity_starter_register` | `token`: the device's ActivityKit push-to-start token (hex); `environment`: `sandbox` or `production` | `{registered:true}`, or `{registered:false,reason:"unavailable"}` on a server without it (404). Registers at `/api/me/thread-live-activity-starter` for the active profile, with its ID; the server then starts the threads Live Activity itself when a thread starts working and the sign-in has none, with that profile ID and a registration ID in its attributes. Register again after switching profiles: the token moves to the active one on the same server; unregister it from a profile on another server |
| `live_activity_starter_unregister` | optional `profile_id`: the profile the token was registered for (default: the active one) | `{unregistered}`, best effort, before signing out or when the device moves to a profile on another server, where the old server would otherwise keep starting activities; a 404 counts as done |
| `open_notification` | `url`: a server-scoped Luft URL; optional `account`: the handle of the account it belongs to; optional `user`: the handle of the person it's for | null; switches to the saved profile on that server signed in as `user` with the account (the active one first) and to the account, then navigates. Signed out, it waits for sign-in like `navigate`; an account no profile has is an error that changes nothing |
| `delete_account` | none | null; deletes personal account and removes active profile |

Thread prompts (`start_thread` and `send_message`) accept up to four `attachments`, each `{name, mime_type, data_base64}` with 1 byte to 1 MiB of decoded data. Text may be empty when files are present. Changing either text or files changes the retry identity. Attachment sends require a connection and never enter the text-only offline outbox; a failure leaves the caller's files and draft available to retry. Authorized message history includes those same attachment objects. Apple clients offer Photos and Files, normalize library photos to bounded JPEGs, and preview received files through QuickLook in disposable private temporary files.

Thread history and inbox rows expose `reauthorization_required` when the persisted
owner delegation is absent or expired. `can_reauthorize` is an owner-only action
hint; the core hides it while working, archived, or in an uncertain outcome.
Native edges show the state and an **Authorize future messages** action, not an
automatic retry. A cached required state blocks composing a queued reply in the
mobile core. Consent preserves drafts and does not flush the outbox. The server,
not this presentation hint or cached state, remains the authority for every write.

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

These requests target the selected Luft origin, which owns threads, lounges and DMs in its own database. DMs retain the private `direct` kind and the `directs` list; they use the same message/read operations as lounges. The Luft server brokers Tuist data for previews, projects and accounts. Preview links and media use Luft URLs, while object-storage URLs remain unchanged. The headless Luft origin serves no HTML shell, Vite or frontend static files; standalone web sources remain outside its deployment.

Every view also contains `navigation: {tab,thread_id,lounge_id,dm_id,compose,snooze,path,revision}`. `thread_id`, `lounge_id` (the Lounges tab's open lounge) and `dm_id` (the DMs tab's) are nullable and survive tab selection; `snooze` is true while the open thread's snooze choices show over it (`/threads/{id}/snooze`, which the Live Activity links to; any other navigation clears it). `compose` is `text` or `dictation` while Start conversation is open on the Threads root (`/threads/new` and `/threads/new/dictation`; the dictation route is accepted only as an internal path, never from a scheme or web link), and null otherwise: any other navigation or tab selection clears it. iOS and macOS present the sheet while it is set and send `navigation_back` when the person dismisses it or threads are unavailable; Android and GPUI don't present it yet and show the Threads root; `path` describes the visible destination. Revision is process-local and increases on navigation changes; ignore older view revisions within the same session generation. Edges bind native tab/stack controls to this state, send user actions back through the operations above, and fetch conversation data through `thread`, or `lounge` for `lounge_id` and `dm_id` (DMs use the same lounge operations; navigation itself performs no network requests). See the workspace README's Deep links section for URL scoping, launch examples and reserved web URLs. Navigation is in memory only, never in the credential vault.

Sign-in uses the Luft server's static public PKCE client (`6653b77b-b787-4eb2-b955-8380ea5f1478`) with the exact `luft://oauth-callback` redirect. Desktop callers use `http://127.0.0.1:<port>/callback` instead. The Luft server brokers Tuist OIDC, keeps encrypted Tuist tokens server-side and issues signed Luft access JWTs (`iss=luft`, up to one hour) plus opaque rotating refresh tokens backed by 30-day sessions. Native clients never receive Tuist credentials.
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

Loading an old mobile vault drops profiles whose access tokens lack `iss=luft` and writes the vault back, so those users sign in to Luft again. This includes earlier macOS builds that used the Tuist app's Keychain session. Luft never touches the shipping app's items. GPUI uses separate files: `Directories::from_env` appends `/luft` to config/state/data bases and does not reuse CLI credentials or its selected Tuist origin; desktop startup overrides use `LUFT_URL`, not `TUIST_URL`.
