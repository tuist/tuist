# Tuist Labels

Prepare rack labels with **`tuist-labels`**, preview them in your browser, and
print through a nearby computer's Chrome tab. Currently supports the **Brady
M211**. Zen/Firefox can use the control/preview page but cannot connect to
Bluetooth. No native helper, printer driver or extension is needed on the Mac.

This is an early internal tool, not a command in the main Tuist CLI or a hosted
production service. It supports one reviewed print attempt and an optionally
authorized separate cut, not unattended batch printing. A prototype was physically
tested with an M211 and M21-750-427 supply; the operator confirmed correct text and
clean separation. Software tests do not access hardware.

## Who runs what?

- **Job host (an orb or your computer):** runs the server and `tuist-labels` CLI.
- **Mac beside the printer:** opens one private relay link in Chrome and selects
  the printer. It does not need Node, this repository, or a local helper.
- **Anyone preparing labels:** uses the CLI on the job host or opens the private
  control link in Zen/Firefox/Chrome. Only share links with trusted operators.

## For colleagues

Use the reviewed **`tuist-labels` Go binary** for your OS/architecture, or open a
private control link from a session owner. No Node, Elixir, repository checkout,
printer driver or native Bluetooth helper is needed on the colleague's machine.
The host maintainer builds binaries with `make dist`; automated publication and
an installer are not configured yet. Do not use `npm install` to install the CLI.

The application is **Phoenix LiveView + Noora**; session and queue updates are
pushed through Phoenix PubSub. Only a small browser hook handles the official
Brady Bluetooth SDK. Chrome is the Bluetooth endpoint, not the server. The CLI
can run on another machine with access to the authenticated HTTPS host.

## Install once on the job host (maintainers)

Requires Elixir 1.18+/OTP 25+, Go 1.22+, Node 24.12+ **for building assets only**,
libvips tools (`vips`) and DejaVu Sans. On Ubuntu, the image/font packages are
`libvips-tools fonts-dejavu-core`; on macOS use libvips and install DejaVu Sans.
From `tools/tuist-labels`:

```sh
make setup
export PATH="$PWD/bin:$PATH"
./bin/tuist-labels --help
```

`make setup` resolves locked Mix/npm dependencies, bundles Noora/LiveView/Brady
assets and builds the Go binary. Node is not used by the running server or CLI.
The Phoenix host uses the local Noora path dependency from this monorepo; retain
that checkout layout. No separate Node server or sidecar runs.

## Start and prepare labels

For a job host beside the printer:

```sh
make serve
```

The server is **preview-only by default**, listening on loopback port 3077. In a
second terminal on the same host:

```sh
tuist-labels init http://localhost:3077
printf 'RACK-02-SW01\nRACK-02-P09\n' > /tmp/labels.txt
tuist-labels submit-text /tmp/labels.txt 38.1 10
tuist-labels status
```

`init` prints two private links. `submit-text` renders one preview per line and
returns `{"queued":2,"state":"preview-only"}` for this example. `status` returns
JSON with preview jobs, approval state and fresh relay/printer/supply status.
You can also use `tuist-labels submit-png label.png` for a pre-rendered image.

### If the job host is an orb

An orb cannot use your Mac's Bluetooth directly. Start a supervised service with
an HTTPS portal, not a detached process:

```sh
amp orb service start tuist-labels --command 'mix phx.server' --port 3077 --portal
```

Use its returned HTTPS origin for the browser links while the CLI calls the
loopback API:

```sh
tuist-labels init http://localhost:3077 https://YOUR-PORTAL-ORIGIN
```

Outside Amp, configure `HOST`/`PORT` and use a trusted authenticated HTTPS proxy
for remote browser access. Set `PUBLIC_URL` to its external HTTPS origin so
Phoenix accepts same-origin WebSocket connections. Amp services set it for you.
Plain remote HTTP cannot use Web Bluetooth. `SECRET_KEY_BASE` can preserve signed
browser cookies across host restarts; the default key is ephemeral. API sessions
and queued jobs remain memory-only either way.

### Connect and preview

Open the private **relay link in Chrome** on the computer near the printer. Wait
for “SDK ready”, click **Connect M211**, and select the printer in the chooser.
Approve Bluetooth permission manually if prompted. Keep this single relay tab
open. Open the separate **control link in Zen or Chrome** to inspect previews or
compose more. `tuist-labels links` displays the links again; protect them like
passwords. If portal sign-in loses the fragment, reopen the full link afterward.

Run `tuist-labels status` and check `relay.connected`, `relay.stale`, printer name,
supply and printable zones before any output. A successful submission or a page
load is not evidence of a Bluetooth connection.

Text files contain one label per line; submission creates previews, **not prints**.
At most 50 labels per request and 100 per session. PNGs are flattened to white.
Text preview dimensions are illustrative at 203 dpi, not guaranteed physical
dimensions. Check cartridge and printable zones before authorizing a print.
Brady's SDK preserves image aspect ratio and fits it to the supply's printable
zone; continuous media length may depend on that ratio.

## Explicit single-use printing

An approval file has this shape (all placeholder values must be replaced):

```json
{
  "id": "replace-with-new-reviewed-approval-id",
  "sessionId": "replace-with-cli-session-id",
  "text": "RACK-02-TEST",
  "printer": "replace-with-reported-printer-name",
  "supply": "replace-with-reported-supply-part",
  "allowCut": false
}
```

After the operator approves the exact label and printer:

1. Use `tuist-labels status` to record the session ID, printer name and supply.
2. Create a private approval JSON **outside the checkout** with the fields above
   (also available in `authorization.example.json` for source users). Replace
   every placeholder. Set `text` to the exact approved label. Choose a new `id`
   for this approval (letters, digits, `_` or `-`). Leave `allowCut` false unless
   a separate cut has also been explicitly approved.
3. Restart the server with `M211_AUTHORIZATION=/absolute/path/authorization.json`
   and the same `M211_STATE_DIR`/`M211_SESSION`. For an Amp service, include these
   environment assignments in its service command. The server restores the
   matching unexpired CLI session. **Queued images/status are lost on restart.**
4. Refresh the existing relay tab and reconnect; do not open competing relay tabs.
   Re-submit the exact approved text, inspect the preview, and obtain its job ID
   from `tuist-labels status`. An uploaded PNG's title is `Uploaded PNG`;
   authorize that title only after reviewing the actual image. Control
   credentials are trusted.
5. Run the explicit command only after approval:

```sh
tuist-labels print-one JOB-ID
tuist-labels status
```

One copy prints with automatic cutting disabled. If the operator separately
approved a cut and the authorization contains `allowCut: true`:

```sh
tuist-labels cut-once
tuist-labels status
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

- Runtime paths and `M211_*` environment variables deliberately retain their
  original names: existing private credentials and consumed dispatch markers
  must not be silently abandoned by a product rename. `init` refuses to overwrite
  credentials at `~/.config/m211-bridge/session.json` (0600). Set `M211_STATE_DIR`
  in server and CLI processes for an isolated state directory, or `M211_SESSION`
  for a specific credential file. Keep state outside Git. Sessions expire after
  eight hours; choose a new state directory for a new session, not for a retry.
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

## Development and distribution

From `tools/tuist-labels`:

```sh
make setup
make test
mix compile --warnings-as-errors
mix format --check-formatted
npm run format:check
GOWORK=off go vet ./...
make dist
make serve
```

`make dist` cross-compiles standalone, CGO-free CLI binaries for macOS, Linux
and Windows, arm64 and amd64, under ignored `dist/`. Review/distribute the right
binary to colleagues; put it on their PATH. No credentials, approvals or dispatch
markers are packaged. No registry publication or automatic release is configured.
`GOWORK=off` keeps this independent module outside the infrastructure workspace.

The ExUnit/Go tests cover role isolation, real PNG generation, atomic rejection,
relay leases, session expiry, single dispatch under concurrency/restart,
separate cut authorization, filesystem failure, private credentials and uncertain
HTTP responses without retries. No test prints.
Actual Firefox is not part of this suite; unsupported-Bluetooth UI can be checked
in Chromium without Bluetooth support. Hardware verification requires an explicit
operator-authorized print and physical confirmation.

Official references: [Web API](https://sdk.bradyid.com/web_api_documentation/),
[supported components](https://sdk.bradyid.com/supported_components/),
[browser support](https://github.com/whatwg/bluetooth/blob/main/implementation-status.md).
