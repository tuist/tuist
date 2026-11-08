# M211 label bridge

Prepare label images and submit commands from a Node CLI (including in an orb),
with a nearby computer's **Chrome tab** as the Bluetooth endpoint. Zen/Firefox
can use the control/preview page but **cannot connect to Bluetooth**. No native
helper, printer driver or browser extension is needed.

This is a standalone internal tool, not a Tuist CLI command or production service.
It deliberately supports one reviewed print attempt and an optionally authorized
separate cut, not unattended batch printing. The prototype was physically tested
with a Brady M211 and M21-750-427 supply: correct label text and clean separation
were confirmed by the operator. Tests below do not access hardware.

## Start in preview-only mode

Requires Node 22+ and a system font (Linux: DejaVu Sans). From this directory:

```sh
npm ci --ignore-scripts
npm test
npm start
```

The server binds to loopback on port 3077 by default. Configure `HOST`/`PORT` for
your host. For a remote Chrome relay, use an authenticated **HTTPS** origin or an
Amp portal. An orb never accesses the Mac's Bluetooth directly. In an orb, start
a supervised service from the repository root, rather than a detached process:

```sh
amp orb service start m211-preview --command 'node tools/m211-bridge/server.mjs' --port 3077 --portal
```

The CLI can call the loopback API while browser links use the returned HTTPS
portal origin. In another terminal, from this directory:

```sh
node cli.mjs init http://localhost:3077 https://YOUR-PORTAL-ORIGIN
node cli.mjs links
node cli.mjs submit-text labels.txt 38.1 10
node cli.mjs submit-png label.png
node cli.mjs status
```

`init` refuses to overwrite credentials. The default file is
`~/.config/m211-bridge/session.json` (0600). Set `M211_STATE_DIR` in both server
and CLI processes for an isolated state directory, or `M211_SESSION` for a
specific credential file. Keep state outside Git; local `state/` is ignored too.
Sessions expire after eight hours; use a new state directory for a new session.

Open the private **relay link in Chrome** on the computer near the printer. Wait
for “SDK ready”, click **Connect M211**, and select the printer in the chooser.
Approve Bluetooth permission manually if prompted. Keep this single relay tab
open. The separate control link works in Zen. Protect both links like passwords.
If portal sign-in loses the fragment, reopen the full private link after sign-in.

Text files contain one label per line; submission creates previews, **not prints**.
At most 50 labels per request and 100 per session. PNGs are flattened to white.
Text preview dimensions are illustrative at 203 dpi, not guaranteed physical
dimensions. Check cartridge and printable zones before authorizing a print.
Brady's SDK preserves image aspect ratio and fits it to the supply's printable
zone; continuous media length may depend on that ratio.

## Explicit single-use printing

After the operator approves the exact label and printer:

1. Use `status` to record the session ID, printer name and supply part number.
2. Copy `authorization.example.json` to a private file **outside the checkout**.
   Replace every placeholder. Set `text` to the exact approved label. Choose a
   new `id` for this approval (letters, digits, `_` or `-`). Leave `allowCut` false
   unless a separate cut has also been explicitly approved.
3. Restart the server with `M211_AUTHORIZATION=/absolute/path/authorization.json`
   and the same `M211_STATE_DIR`/`M211_SESSION`. For an Amp service, include these
   environment assignments in its service command. The server restores the
   matching unexpired CLI session. **Queued images/status are lost on restart.**
4. Refresh the existing relay tab and reconnect; do not open competing relay tabs.
   Re-submit the exact approved text, inspect the preview, and obtain its job ID
   from `status`. An uploaded PNG's title is `Uploaded PNG`; authorize that title
   only after reviewing the actual image. Control credentials are trusted.
5. Run the explicit command only after approval:

```sh
node cli.mjs print-one JOB-ID
node cli.mjs status
```

One copy prints with automatic cutting disabled. If the operator separately
approved a cut and the authorization contains `allowCut: true`:

```sh
node cli.mjs cut-once
node cli.mjs status
```

`cut-once` sends only a cut, never a new print or feed. No feed, ownership reset,
firmware or printer configuration API is exposed. SDK confirmation still requires
the operator to check physical output. **Never automatically retry an uncertain
print or cut.**

Before granting dispatch the server exclusively creates and fsyncs
`dispatch-ID.json` (0600) in the state directory; a separate `.cut` marker guards
the cut. Concurrent claims, lost responses and server restarts cannot reuse those
markers. A consumed authorization may have produced nothing if delivery failed:
safety takes precedence over automatic recovery. Never delete a marker or change
the approval ID merely to retry. Inspect the printer and obtain a new explicit
approval first. Keep the same state directory across restarts; losing it loses
the duplicate-dispatch protection. Results and jobs themselves are memory-only.

## Ownership, freshness and security

- SDK 3.3.3 internally preserves `localStorage.ownershipID` and returns a boolean
  from discovery, unlike older public documentation. Refresh/reconnect on the same
  origin/profile retains ownership. **Disconnect & release** intentionally calls
  SDK disconnect, which clears it. No automatic ownership reset is performed.
- A 35-second single-relay lease prevents competing tabs through this UI. Status
  is stale after 35 seconds without a heartbeat. Tab throttling or sleep can make
  a physical connection appear stale; this is a freshness check, not disconnect
  proof. A status button/page load alone does not prove a Bluetooth connection.
- Separate random 256-bit control/relay capabilities scope access to each session.
  Relay can claim queued actions and report results but cannot create them.
  Fragments are removed after intake. No CORS or remote shell execution exists.
  A relay is trusted to report honestly; this is not hardware attestation.
- Bind to loopback by default. Use a trusted HTTPS/authenticated proxy for remote
  access; room capabilities are not a substitute for protecting the host. Session
  creation is rate/bound limited, but this is not hardened for hostile public use.
- SDK JavaScript/WASM are served from the installed pinned npm package under a
  same-origin CSP. Analytics are disabled. Brady's SDK is proprietary and subject
  to its own license; it is a dependency, not vendored or relicensed here.

## Development

```sh
npm test
npm run format:check
```

The HTTP/CLI tests cover role isolation, real PNG generation, atomic rejection,
relay freshness, session expiry, single dispatch under concurrency/restart,
separate cut authorization, and preview-only/configured startup. No test prints.
Actual Firefox is not part of this suite; unsupported-Bluetooth UI can be checked
in Chromium without Bluetooth support. Hardware verification requires an explicit
operator-authorized print and physical confirmation.

Official references: [Web API](https://sdk.bradyid.com/web_api_documentation/),
[supported components](https://sdk.bradyid.com/supported_components/),
[browser support](https://github.com/whatwg/bluetooth/blob/main/implementation-status.md).
