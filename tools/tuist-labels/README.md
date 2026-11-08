# Tuist Labels

Prepare labels through **Atlas MCP** and connect a nearby **Brady M211** using
Chrome. Atlas hosts the Phoenix/Noora connection and approval pages and stores
sessions, images, approvals and dispatch results in PostgreSQL. **No server runs
in each orb or on colleagues' Macs.** This directory contains only the optional
Go CLI; the server lives in `atlas/` and ships with Atlas.

## Normal agent workflow

1. Give your agent the label text or PNGs. Using your personal Atlas connection,
   it calls `manage_label_session` with `action: "create"`, then `submit`.
2. Open the returned **private connection link in Chrome beside the printer**,
   signed into the same Atlas account. Click **Connect M211**, select the printer
   and approve the browser's Bluetooth prompt. Keep that one tab open and the
   computer awake. No CLI, repository, Elixir, Node, drivers or helper is needed
   on this computer. Zen/Firefox cannot provide Web Bluetooth.
3. The agent reads `status` and `preview`, inspects the exact PNG, printer, supply
   and printable zones, then calls `request_print` for that job.
4. Open its **Atlas approval link**. Check the image, printer and installed supply,
   then click **Approve & print one copy**. Only the signed-in owner can approve;
   neither MCP nor a bearer API call can approve output.
5. Inspect the physical result. Printing never cuts automatically. If needed, the
   agent calls `request_cut` after an SDK-confirmed print. Approve that separate
   cut in Atlas; it does not print or feed another label.

Submission is always preview-only. Each session supports one reviewed print
attempt and one separately approved cut, not unattended batch printing. Up to
50 previews can be submitted per request, 100 per session. Sessions expire after
eight hours, approvals ten minutes after request, and relay reports after
35 seconds. Text previews use 203 dpi; their dimensions are not a physical-size
guarantee. The SDK scales to the supply preserving aspect ratio.

MCP actions: `create`; `status` with `session_id`; `submit` with `session_id`,
`items: [{text: "RACK-02-SW01"}]` (or base64 `png`), optional `width_mm`/`height_mm`;
`preview` with `session_id`/`job_id` (base64 PNG result); `request_print` with
`session_id`/`job_id`; `request_cut` with `session_id`. No approval action exists.
The hardware MCP group and `assets:read`/`assets:write` scopes apply; shared-identity
Slack callers are excluded. Existing roles are not granted new permissions.

## Optional Go CLI

Agents should normally use the Atlas MCP connection already available to them.
Operators with an Atlas OAuth bearer token can use the Go binary instead. Set
`ATLAS_TOKEN` securely in the environment; never put it in a command argument,
source file or public thread. It is read anew on each request and never saved.

```sh
tuist-labels init https://atlas.tuist.dev
tuist-labels links
printf 'RACK-02-SW01\nRACK-02-P09\n' > labels.txt
tuist-labels submit-text labels.txt 38.1 10
tuist-labels status
tuist-labels preview JOB-ID label.png
tuist-labels print-one JOB-ID
```

`print-one` returns an `awaiting-approval` job and its `approvalUrl`; **it does not
approve printing**. After the operator approves and verifies the output:

```sh
tuist-labels cut-once
tuist-labels status
```

`cut-once` also requests browser approval, not immediate output. `submit-png`
accepts one or more PNG paths. Preview/session writes refuse to overwrite files.
Commands never automatically retry output requests, including a lost response.

Build with Go 1.22+ from this directory:

```sh
make build
./bin/tuist-labels --help
make test
GOWORK=off go vet ./...
make dist
```

`make dist` creates CGO-free macOS/Linux/Windows binaries for arm64 and amd64 in
ignored `dist/`. No installer or automated binary publication is configured.
Review/distribute the binary; the CLI is not installed through npm. Atlas assets
use a pinned npm dependency at build time only, not a Node server.

## Safety and migration

- Atlas ownership and current permissions are checked on every operation.
  Private relay capabilities grant transport/status only, never preparation or
  approval. PostgreSQL stores only their SHA-256 hashes. Links are secrets.
- PostgreSQL row locks serialize claims across replicas. The `dispatched` state
  commits before Chrome receives permission to output. Restart, competing
  claims and lost responses never return a consumed job to the queue. A crash
  can therefore consume an approval without printing. There is no retry worker.
- **Never automatically retry uncertain output.** Inspect the printer first.
  A new session and new human approval represent a new deliberate operation,
  not recovery of an old claim. `sdk-confirmed` is not physical confirmation.
- The relay is trusted to report honestly, not hardware-attested. Keep the tab
  open; sleeping/throttled tabs can become stale. Web Bluetooth requires HTTPS
  (or local development loopback) and an explicit initial user chooser gesture.
- SDK 3.3.3 manages `localStorage.ownershipID` internally. Same-origin/profile
  refresh preserves it; moving from a prototype portal to Atlas does not migrate
  browser-origin ownership. Release the old connection deliberately first; never
  reset printer ownership automatically. **Disconnect & release** is explicit.
- No feed, firmware, configuration, ownership-reset or remote-shell API exists.
  SDK analytics are disabled. Its JavaScript/WASM are build outputs of the pinned
  proprietary Brady package, not vendored or relicensed here.
- CLI paths retain `M211_STATE_DIR`, `M211_SESSION` and the default
  `~/.config/m211-bridge/session.json` (0600). Legacy `controlToken` sessions are
  rejected without modifying credentials or dispatch markers. Keep those files;
  use a new private path for a genuinely new Atlas session after checking old
  output. No old preview, authorization or consumed marker is imported/replayed.
- Atlas data survives restarts and follows [its export/retention inventory](../../atlas/data-export.md#label-printing).
  Integration still needs the normal Atlas release/migration process; a PR does
  not provision or deploy a separate service.

Backend and UI checks live in Atlas's test suite; this directory's tests cover
the Go HTTP contract, token rotation, private state and no-retry behavior. Tests
must never access a real printer without fresh explicit authorization. Earlier
prototype hardware success does not validate a new Atlas deployment.

Official references: [Web API](https://sdk.bradyid.com/web_api_documentation/),
[supported components](https://sdk.bradyid.com/supported_components/),
[browser support](https://github.com/whatwg/bluetooth/blob/main/implementation-status.md).
