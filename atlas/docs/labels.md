# Tuist Labels

Prepare labels through **Atlas MCP** and connect a nearby **Brady M211** using
Chrome. Atlas hosts the Phoenix/Noora connection and approval pages and stores
sessions, images, approvals and dispatch results in PostgreSQL. **No server runs
in each orb or on colleagues' Macs.** Agents use Atlas MCP; Chrome provides only
connection/status and exact-operation approval. There is no separate CLI,
Labels dashboard, sidebar entry or browser label-preparation workflow.

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
- The removed prototype CLI's private credentials and dispatch markers are not
  read, modified, imported or replayed. Keep any existing consumed markers;
  inspect previous output before deliberately starting a new Atlas session.
- Atlas data survives restarts and follows [its export/retention inventory](../data-export.md#label-printing).
  Integration still needs the normal Atlas release/migration process; a PR does
  not provision or deploy a separate service.

Backend, MCP and connection/approval checks live in Atlas's test suite. Tests
must never access a real printer without fresh explicit authorization. Earlier
prototype hardware success does not validate a new Atlas deployment.

Official references: [Web API](https://sdk.bradyid.com/web_api_documentation/),
[supported components](https://sdk.bradyid.com/supported_components/),
[browser support](https://github.com/whatwg/bluetooth/blob/main/implementation-status.md).
