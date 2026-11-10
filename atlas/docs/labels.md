# Tuist Labels

Prepare and print labels through **Atlas MCP** on a nearby **Brady M211** connected
through Chrome. Atlas hosts the Phoenix/Noora connection and review pages and stores
sessions, images, batches and dispatch results in PostgreSQL. **No server runs
in each orb or on colleagues' Macs.** Agents use Atlas MCP; Chrome provides only
the Bluetooth connection, status and, optionally, batch review. There is no
separate CLI, Labels dashboard, sidebar entry or browser label-preparation workflow.

## Normal agent workflow

1. Give your agent the label text or PNGs. Using your personal Atlas connection,
   it calls `manage_label_session` with `action: "create"`, then `submit`.
2. Open the returned **private connection link in Chrome beside the printer**,
   signed into the same Atlas account. Click **Connect M211**, select the printer
   and approve the browser's Bluetooth prompt. Keep that one tab open and the
   computer awake. No CLI, repository, Elixir, Node, drivers or helper is needed
   on this computer. Zen/Firefox cannot provide Web Bluetooth. If the page says
   it lost the private token (sign-in round trips drop the `#token` part of the
   link), it asks Atlas for a new one itself: the signed-in owner's connection
   page gets a fresh relay credential whenever no other relay tab is active.
3. The agent reads `status` and `preview`, inspects the PNGs, printer, supply
   and printable zones, then calls `print`. **While the tab is connected the agent
   operates the printer directly**, unless review was requested: at most 20 labels
   per batch, and only once the session's previous batch has finished. A larger
   batch waits for owner review.
   Disconnecting or closing the tab stops it.
4. Watch the labels come out. The connection page lists every label in the session
   with its print and cut result; the agent reads the same through `status`.

**Review is optional for batches of up to 20 labels and required above that.** When you want to see a batch before it prints, ask the agent
to pass `approval: true`. It then sends an Atlas review link that shows every label
in the batch, in print order, with its preview, the printer, the supply and the
count. One click on **Approve** prints the whole batch. Only the signed-in owner can
approve, in the browser; neither MCP nor a bearer API call can approve output.
Unapproved batches return to preview ten minutes after the request.

## Batches and cutting

`print` takes `job_ids` in print order (default: every preview-only label in
submission order), at most 100; more than 20 needs `approval: true`. A batch is printed **one label at a time**: the
relay claims a label, calls `printBitmap` for exactly that image with one copy and
the SDK cut option *Never*, then, unless the batch was queued with `cut: false`,
calls `cut()`. Only then does it claim the next label. The installed M21-750-427 is
a continuous wrap, so cutting after every label is the default; `cut: false`
produces one uncut strip to cut by hand. `cut` sends one standalone cut and nothing
else, for example to detach a strip.

We chose this over `printBitmaps` with the *EndOfLabel* cut option because the SDK
reports one boolean for a whole `printBitmaps` job: after a failure nobody would
know how many labels came out. Separate print and cut calls give each label its own
`printResult` and `cutResult` and match the print-then-cut sequence verified on
production on 9 Nov 2026. The cost is one extra Bluetooth round trip per label.

PostgreSQL enforces the order: a label can only be claimed after every earlier
label in its batch is `sdk-confirmed`, and only one operation per session is in
flight. A label counts as `sdk-confirmed` only when its print and requested cut
both returned success; otherwise it is `uncertain`, with the separate results
recorded. **An uncertain label, or a relay reload during output, stops all queued
output**: the remaining labels return to `preview-only` with a note saying why they
did not print. Nothing printed or uncertain is ever queued again; inspect the
printer, then queue the unprinted labels again or submit a label again to reprint it.
A queued batch must start within ten minutes and finish within one minute per label
after that; labels the relay did not reach by then return to preview unprinted.

Up to 50 previews can be submitted per request, 100 per session. Sessions and their
relay credentials expire after **eight hours without qualifying activity**, not
eight hours after creation. Each successful connected relay report or owner request
through the personal API/MCP connection resets the deadline to eight hours from now.
Explicit dashboard actions (approval or relay credential recovery) also renew it;
automatic dashboard status/image refreshes, relay status/image reads, disconnected
reports and failed requests do not. Keep the connected Chrome tab reporting to work
past the original deadline without a new link or Bluetooth pairing. Closing it,
disconnecting or putting the computer to sleep stops connected reports; without
further owner/agent activity the session and credential expire within eight hours.
An open tab still reporting a connected printer counts as active even between prints.
Expiry cannot be undone by a late report or request.

Existing unexpired sessions benefit automatically after deployment, using the same
relay link and credential; no page reload or new pairing is needed for this change.
Already expired sessions stay expired: create one new session and connect it once.
The `expiresAt` in status is the current idle deadline. Relay reports still become
stale after 35 seconds, independently of session expiry. Text previews use 203 dpi;
their dimensions are not a physical-size guarantee. The SDK scales each image to the
supply preserving aspect ratio. MCP `preview` and `status` include `sizing` alongside
the PNG/job: actual bitmap pixels, sizing mode, a warning, and (for zoneless
continuous tape) a nominal page length before margin adjustments and feed/trailer.

## Zoneless continuous tape (M21-750-499)

SDK 3.3.3 reports this nylon tape as width 0.75 inches, height 0 and no printable
zones. Zero height is not a zero-length label: the SDK paginator derives continuous
page length from bitmap width / bitmap height × adjusted tape width. On the M211,
`adjustLabelPosition` caps that width at 0.63 inches (16.002 mm) and applies
orientation/margin adjustments. `setupBanding` fits the image preserving aspect
ratio. `printPageStart` sends the derived page size at 203 dpi and enables the
M211 trailer. **Length follows bitmap aspect ratio, not PNG DPI metadata or the
requested preview millimetres.** Physical cut length includes printer feed/trailer
and must be measured; the nominal page length is not a cut-length guarantee.

Atlas accepts an empty zone list only with an explicit SDK `mediaIsDieCut: false`,
zero supply height and positive width at most 0.75 inches. Missing/invalid metadata,
die-cut supplies and nonempty invalid zones still fail closed. The relay must be
reloaded after upgrading so it reports the continuous-media flag. Atlas snapshots
width, height and that flag as well as printer/supply/zones, checking them at
approval, claim and immediately before SDK output. Reconnect the exact approved
snapshot or make a new request/review; a different snapshot cannot use the old approval.

Zoneless prints follow the same review rules as any other supply. Review and
session previews show the actual bitmap size, nominal SDK page length and the
physical-size warning. Atlas rejects nominal lengths above 200 mm based on actual
PNG pixels, including uploads; declaring smaller preview mm cannot bypass this.
Standalone cuts retain their existing optional review. Ordering, single-flight
dispatch and uncertain-output handling are unchanged.

For the first `larch-runner-a01` hardware test, request **one** label, review its
preview and approve it yourself in Chrome. A 50×10 mm text preview is 400×80 px:
its 5:1 aspect ratio makes the nominal SDK page about **80 mm**, not 50 mm, before
feed/trailer. For approximately 50 mm artwork length with a 10 mm content band,
prepare a PNG with the content centered on a roughly 50×16 mm white canvas
(about 400×128 px); do not merely request 50×10 mm. The tape itself remains
19.05 mm wide: a finished 10 mm-high label requires manual trimming or narrower
stock, not a bitmap setting. First measure the artwork
length/height, total cut tape length and leading/trailing margins, check orientation,
legibility and edge clipping, and confirm exactly one print and one cut with no
duplicate output. Adjust the bitmap only after measuring. If either result is
uncertain, inspect the printer and never retry automatically. This PR alone does
not enable production: normal review, merge and deployment must happen first.

Source: the pinned npm package
[`@bradycorporation/brady-web-sdk@3.3.3`](https://www.npmjs.com/package/@bradycorporation/brady-web-sdk/v/3.3.3),
`dist/bundle.js`: `printBitmap` → `printBitmaps`, paginator
`findFirstPrintableZoneAndLabelHeight` / `adjustLabelPosition`, `setupBanding`,
and `printPageStart`. The [public API documentation](https://sdk.bradyid.com/web_api_documentation/#printbitmap-printbitmaps)
describes aspect-preserving zone fitting but omits this zoneless fallback; the
package implementation, not an invented printable zone, is the source for it.

MCP actions: `create`; `status` with `session_id`; `submit` with `session_id`,
`items: [{text: "RACK-02-SW01"}]` (or base64 `png`), optional `width_mm`/`height_mm`;
`preview` with `session_id`/`job_id` (base64 PNG result); `print` with `session_id`,
optional `job_ids`, `cut` (default true) and `approval` (default false); `cut` with
`session_id` and optional `approval`. No approval action exists.
The hardware MCP group and `assets:read`/`assets:write` scopes apply; shared-identity
Slack callers are excluded. Existing roles are not granted new permissions.

## Safety and migration

- Atlas ownership and current permissions are checked on every operation.
  Output goes only to the owner's own connected relay; the agent needs the
  owner's personal Atlas connection and `assets:write` to queue it. Private relay
  capabilities grant transport/status only, never preparation or approval.
  PostgreSQL stores only their SHA-256 hashes. Links are secrets. Only the
  signed-in owner's connection page can rotate the capability, never while
  another relay tab is active; the replaced one stops working.
- PostgreSQL row locks serialize claims across replicas. The `dispatched` state
  commits before Chrome receives permission to output. Restart, competing
  claims and lost responses never return a consumed job to the queue. A crash
  can therefore consume a label without printing it. There is no retry worker.
- **Never automatically retry uncertain output.** Inspect the printer first.
  Queuing a label again is a new deliberate operation, not recovery of an old
  claim. `sdk-confirmed` is not physical confirmation.
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

Backend, MCP, batch ordering/halting and connection/review checks live in Atlas's
test suite; the relay's SDK calls are not exercised there. Tests
must never access a real printer without fresh explicit authorization. Earlier
prototype hardware success does not validate a new Atlas deployment.

Official references: [Web API](https://sdk.bradyid.com/web_api_documentation/),
[supported components](https://sdk.bradyid.com/supported_components/),
[browser support](https://github.com/whatwg/bluetooth/blob/main/implementation-status.md).
