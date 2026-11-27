# Accounts and Support: local native workspace

This is a bounded local prototype, not a production authentication mode. The
workspace manifest installs two portable Luft Apps from `../../apps/`: Account
Management and Support. Each app owns its models, queries/actions, UI and fixtures;
only the workspace supplies the organization. See [the app contract](../../apps/README.md).
Each app's published `ui/bundle.js` runs in the iOS app's real NSH 0.5.1
native renderer, not a web view. Records come from the server, never Swift.
There is no database or persistence implementation in this directory.

The module defines three pages: the customer list, a customer detail addressed by
record ID, and a new-customer form. NSH's `NavStack`/`NavPage` use a real
`UINavigationController` on iOS, including the system back button and interactive
swipe-back. Status selection uses the system action sheet (`AlertDialog`), and
the form uses native text fields and the email keyboard. The surrounding Luft
shell owns module navigation and the permanent preview banner. Page history is
disposable presentation state; navigating never grants a data capability.

Support adds an inbox, conversation detail and read-only linked customer page.
It depends on Accounts version 1 and explicitly requests `accounts.customer.get`,
not customer writes. Its nullable customer ID is a PostgreSQL UUID foreign key.
The customer page uses the canonical getter; it does not copy customer fixtures
into Support or assume the target app's UI is installed. Native Back returns to
the conversation and then the inbox. Unlinked conversations have no customer link.
Closing/reopening a conversation refreshes the inbox without discarding the stack.

## Build the module

Install the NSH 0.5.1 CLI, then run:

```sh
bash luft/apps/customer-management/ui/build.sh
bash luft/apps/support/ui/build.sh
bash luft/workspaces/customer-management/session/build.sh
```

`NSH_BIN` can name that pinned CLI. The script runs the module's headless native
tests before rebuilding the checked-in **source** bundle. Bytecode is deliberately
not loaded from a server. NSH warns that status-bar access is not granted: this is
intentional; the embedding app owns system chrome.

Commit TSX and bundle changes together. Publication reads `workspace.json` and
the referenced bundle, not TSX. Rebuild and republish after changing presentation.

## Publish, seed, serve locally

The companion `luft-server` tooling owns compilation, PostgreSQL storage,
validation, revision checks and idempotency. From `luft-server/`:

```sh
export CONDUKT_BASHKIT_DISABLE=1 CONDUKT_MICROSANDBOX_DISABLE=1
mix luft.workspace.publish ../luft/workspaces/customer-management/workspace.json --database luft_workspace_demo
mix luft.workspace.seed ../luft/workspaces/customer-management/workspace.json --database luft_workspace_demo
mix luft.workspace.serve --database luft_workspace_demo --port 4210 --connection-file /tmp/luft-workspace.json
```

These are local tooling commands, not production runtime configuration. Database
names must start with `luft_workspace_`. Publishing does not seed records;
fixtures are a separate explicit step. Serving writes a mode-0600 `{url,token}`
connection file. Treat its token as a secret; never commit it, print it, or include
it in screenshots, launch transcripts or test artifacts.

PostgreSQL must already be running locally. Set `LUFT_WORKSPACE_PGUSER` when its
role differs from the server's configured role; the role needs permission to
create these disposable databases. Each database is bound to one organization.
Models compile to ordinary PostgreSQL columns and constraints, with the authored
definition retained in `workspace_catalog`. Republishing a changed model requires
the next version and supports additive fields only; a new required field needs a
valid default. Publication and schema changes commit together. This prototype
does not accept arbitrary SQL or destructive migration scripts.

## Use the same contracts from a local agent

The local server also exposes `/mcp`, independently of native modules. It uses
single-message JSON responses over MCP Streamable HTTP (2025-03-26); it does not
offer server-push events, resources, prompts or a public remote installation.
Its tools are compiled from the installed query/action definitions. A package
with `"ui_modules": []` needs no `ui/` directory and still exposes its contracts.
The native preview renderer requires a UI module; use MCP for a headless workspace.

By default MCP offers only read queries. To expose one mutation in this local
rehearsal, start the server with an explicit action grant:

```sh
mix luft.workspace.serve --database luft_workspace_demo --port 4210 \
  --connection-file /tmp/luft-workspace.json \
  --mcp-action support.conversation.update
```

Repeat `--mcp-action` for additional published actions. Unknown grants fail
startup. These flags restrict **MCP tool exposure**, not the bearer credential:
the preview token still authorizes the existing `/action` API and all local
queries. Do not treat it as a read-only or actor-scoped token, put it in a prompt,
or connect it to a production session. Remove an old disposable connection file
before restarting the server; exclusive creation deliberately refuses overwrite.

The connection can be consumed by the existing Condukt client in a local process
running on the same machine as the server. Keep the credential in host memory:

```elixir
connection = "/tmp/luft-workspace.json" |> File.read!() |> Jason.decode!()
server = %Condukt.MCP.Server{
  name: "workspace",
  transport: {:streamable_http,
    url: connection["url"] <> "/mcp",
    headers: %{"authorization" => "Bearer " <> connection["token"]}}
}
{:ok, client} = Condukt.MCP.Client.start_link(server)
Condukt.MCP.Client.tools(client)
```

The resulting catalog includes `query.support.conversation.list` and
`query.accounts.customer.get`. A granted `action.support.conversation.update`
accepts `{request_id, input: {id, expected_revision, values}}`. Obtain the UUID
from `workspace_request_id` and keep the same UUID/input across an uncertain
retry. Successful writes return the saved row immediately, without depending on
a follow-up list refresh. Repeating the same submission returns its stored
result; a new submission with a stale revision fails rather than overwriting.
List tools explicitly report a 100-record bound in their descriptions; they are
not exhaustive search or export APIs. Record values are untrusted content.

The server test `a real MCP client uses cross-domain contracts without installing
any UI` publishes Accounts and Support after deleting their bundles, then uses
real loopback HTTP and PostgreSQL to create/link/read/close a conversation and
check replay, stale revisions and persistence through a second connection. The
other MCP cases cover default-denied writes, closed inputs, token checks,
protocol metadata, omitted arguments and browser-origin rejection. These are
deterministic tool-contract tests, not a live model conversation or a usability
comparison against the Inbox. No authenticated Luft Threads routing is changed.

## Opt in on the iOS simulator

Build/install Luft normally. On the Mac hosting both the simulator and local
server, launch with the connection file's environment values (disable shell
tracing first):

```sh
set +x
SIMCTL_CHILD_LUFT_WORKSPACE_URL="$(jq -r .url /tmp/luft-workspace.json)" \
SIMCTL_CHILD_LUFT_WORKSPACE_TOKEN="$(jq -r .token /tmp/luft-workspace.json)" \
xcrun simctl launch booted dev.tuist.code
```

Terminate an already-running app before relaunching with different environment.
`LUFT_WORKSPACE_URL` and `LUFT_WORKSPACE_TOKEN` are read only by the simulator
preview root. Even an incomplete opt-in stays in preview and displays an error;
it never falls back to saved profiles or `luft.work`. Device and macOS builds
have no preview root. Launching without either variable preserves the ordinary
signed-in/signed-out paths.

The separate preview shell has a permanent preview banner and manifest-driven
sidebar. It does not boot production identity, notifications, the credential
vault or Keychain. Its HTTP-only host refuses all storage and identity services.
Rust validates loopback HTTP or explicit HTTPS origins, published definitions,
capabilities, inputs and responses. The JS VM has one `workspace` host handler,
bounded memory/execution/nodes, disposable storage, and no granted networking,
filesystem or clipboard access. It never receives connection credentials.

## Contextual session experiment

In the preview sidebar, choose **Sessions → Support handoff**. This is a fixed,
host-bundled fixture session, labeled **not a live session**. It has no model,
provider, production identity or composer. Its historical summary remains at
revision 1 even after the business record changes.

**Open support record** sends a typed `{model, id}` reference to Rust's
`workspace_open`. The core requires the selected module to own that model and
declare its getter, validates the UUID, and fetches the canonical record every
time. It stores that record separately from the 100-row inbox. No mutation or
model request occurs on opening. Failed opens stay on the session with an error.

The harness reuses Support's exact conversation and customer pages. NSH's single
native navigation stack supports **session → conversation → customer → Back →
conversation → Back → session**, including interactive swipe-back on iOS.
**Refresh conversation** fetches again; opening a linked customer also performs
a fresh getter. **Open support inbox** provides the existing browsing route as
a control without leaving the stack. UI modules and generated conversation cards
gain no additional credentials or production capabilities.

Close/Reopen sends the displayed ID, expected revision and explicit desired
status. Unknown outcomes show **Retry submission**, which repeats the retained
request instead of generating a second write. A known successful write followed
by a failed read returns its saved result with a refresh warning. Switching
modules or disconnecting still discards transient history and pending requests;
reconcile unknown effects after reconnect before making a new submission.

The trusted session source is `session/App.tsx`, importing the same `Support.tsx`
used by the published Inbox. Its source bundle ships only in `LuftIOS` simulator
resources, separately from server-published app bundles. Rebuild it before
building the iOS host after shared Support changes. This experiment tests
contextual navigation and deterministic actions, not authenticated Threads
integration, natural-language selection or a user preference for conversations.

## Check the slice

1. Launch opted in: the server's two customer fixtures should appear under **Customers**.
2. Open a customer, then return with the system back button or an edge swipe.
   Opening a detail page must not submit an action.
3. Choose **Add customer**. Submit an empty name: show validation without sending
   an action. Correct the preserved form, enter a name, optional email and status; create.
   The core refreshes the list only after the authoritative saved record passes
   validation.
4. Open a customer's detail and change its status in the system action sheet:
   send its ID and expected revision. Canceling the sheet must not submit. A
   revision conflict requires reloading, never an optimistic overwrite.
5. Relaunch against the same database: the server should retain created records
   and status changes.
6. Disconnect explicitly, or stop the server and issue a refresh/action. Once a
   transport failure is detected, the core clears source, rows, pending writes
   and credentials. The module disappears; reconnect must be explicit.
7. Open the host sidebar and select **Support → Inbox**. Open **Build cache
   setup**, then **View customer details**: Northstar Labs must load through
   `accounts.customer.get`. Back must return to the conversation, then inbox.
8. Open **Question from a new visitor**: show **No customer linked**, without a
   customer-navigation button. Close it; its detail must remain open with the new
   revision. Back and relaunch must show the saved status.

There is one automatic retry for an `offline` transport result, with exactly the
same serialized body/request UUID. HTTP failures are not automatically retried.
**Retry submission** repeats a pending request after a retryable HTTP or malformed
response using its original UUID; a deliberate new submission gets a new UUID.
After a sustained transport loss the pending request is discarded along with the
connection. If a write's outcome was unknown, reconnect and inspect the list
before submitting again. Nothing is queued offline. No background connectivity
monitor is installed: fail-closed behavior takes effect when a request detects
the loss, not merely when the server process exits.

Current prototype limits: at most 100 rows, string/enum/reference fields, one selected
module's list at a time; no search, pagination, deletion, production auth or
distribution. Host snapshots update the running module through events, preserving
page history and drafts. Switching modules, reconnecting or disconnecting disposes
that module's VM and local state. A linked customer page is a fetched snapshot,
not a realtime subscription; reopen it to fetch again. UI state
is presentation only; authoritative records, revision semantics, selection, retry identity,
capability checks and transport decisions stay in Rust/server.

## Core checks (Linux or macOS)

From `luft/`, using its pinned Rust toolchain:

```sh
cargo test -p tuist-app-core --locked
cargo clippy -p tuist-app-core --all-targets --locked -- -D warnings
```

The public-interface integration tests use an HTTP-only host that fails on any
vault/platform action, and independently check additive model versions, defaults,
null optional fields and the server's 4,000-byte string bound. Headless NSH tests
prove native module rendering/interaction, but do not replace an iOS simulator
build and interaction proof.
