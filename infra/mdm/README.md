# Fleet MDM runbook

Self-hosted Apple MDM for the Mac runner fleet (BER1 rack program). The
footprint is deliberately tiny: enroll zero-touch through Apple Business
Manager automated device enrollment, create the service account, install
the fleet SSH key, enable Remote Login, allow USB accessories — then get
out of the way. Everything else on a host is installed and kept
converged by the operator SSH bootstrap (`infra/macos-host-bootstrap`).

## Components

| Component | Image | Role |
|---|---|---|
| nanomdm | `ghcr.io/micromdm/nanomdm` | MDM protocol server (check-ins, command queue, APNs push) |
| scepserver | `ghcr.io/tuist/scepserver` (built from `infra/mdm/scep`) | SCEP CA issuing per-device MDM identity certificates |
| nanodep (depserver + depsyncer) | `ghcr.io/micromdm/nanodep` | ABM device-enrollment API: token exchange, DEP profile assignment, continuous sync/auto-assign |
| mdm-enroller | `ghcr.io/tuist/mdm-enroller` (built from `infra/mdm/enroller`) | Serves the enrollment profile and bootstrap pkg; reacts to nanomdm's webhook by enqueuing the on-enroll command sequence |
| Postgres | CNPG cluster in the same namespace | Storage for nanomdm + nanodep (schemas vendored in the chart, applied at initdb) |

Deployed by `.github/workflows/mdm-deployment.yml` from
`infra/helm/mdm` into the staging cluster, namespace `mdm`.

Public endpoints (staging):

- `https://mdm-staging.tuist.dev/mdm` — device check-in/command endpoint (ServerURL)
- `https://mdm-staging.tuist.dev/scep` — SCEP
- `https://mdm-staging.tuist.dev/enroll` — enrollment profile (what the DEP profile's `url` points at)
- `https://mdm-staging.tuist.dev/static/bootstrap.pkg` — signed bootstrap package
- `https://mdm-staging.tuist.dev/v1/...` — nanomdm operator API (HTTP Basic, user `nanomdm`, password = `nanomdm-api-key`)
- `https://mdm-dep-staging.tuist.dev/v1/...` — nanodep operator API (HTTP Basic, user `depserver`, password = `nanodep-api-key`)

The enroller's `/webhook` is cluster-internal on purpose (not routed by
the ingress).

**The device-facing hostname is forever.** The MDM protocol cannot
change an enrollment's ServerURL; a hostname change means re-enrolling
(re-provisioning) every device. `mdm-staging` is fine for the prototype
gauntlet because the fleet's normal recovery path is a DFU restore that
re-enrolls anyway, but the production rack enrolls against a hostname
we intend to keep (e.g. `mdm.tuist.dev`).

## Enrollment flow (zero-touch)

1. A Mac mini boots factory-fresh (or DFU-restored to the pinned IPSW)
   with Ethernet.
2. Setup Assistant contacts Apple, learns the device is assigned to our
   MDM (default Mac assignment in ABM, kept current by depsyncer
   auto-assigning newly synced devices), and fetches the DEP profile:
   `await_device_configured` + `auto_advance_setup` + all skippable
   panes skipped, profile `url` = `/enroll`.
3. The device downloads the enrollment profile, does SCEP against
   `/scep` (RSA 2048 identity issued by our CA), and enrolls against
   `/mdm`. TLS is public Let's Encrypt; no anchor certs needed.
4. nanomdm fires its webhook at the enroller, which enqueues, in order:
   - `AccountConfiguration` — creates the admin service account
     (default short name `tuist`) from the stored password hash and
     skips Setup Assistant account creation.
   - `InstallProfile` — the USB-accessory payload
     (`com.apple.applicationaccess` with `allowUSBRestrictedMode=false`).
   - `InstallEnterpriseApplication` — the signed bootstrap pkg with an
     inline manifest. Its postinstall enables Remote Login, sets
     `pmset autorestart 1`, and installs the fleet SSH public key into
     the service account's `authorized_keys`.
   - `DeviceConfigured` — releases the device from "awaiting
     configuration".
5. The machine lands at the login window, SSH-reachable, with nobody
   having touched it. The operator SSH bootstrap takes it from there.

## Manual ceremonies

All secret material lives in a single 1Password item **`MDM`** in the
env's vault (`tuist-k8s-staging`), synced into the cluster by ESO.
Create it first.

### 0. Seed the 1Password item

Generate and store these fields (field names are load-bearing —
`infra/helm/mdm/templates/secrets.yaml` reads them):

```bash
openssl rand -hex 32   # nanomdm-api-key
openssl rand -hex 32   # nanodep-api-key
openssl rand -hex 16   # scep-challenge
openssl rand -hex 16   # enroll-token
```

SCEP CA (10-year, RSA; keep the key only in 1Password):

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout scep-ca.key -out scep-ca.pem -subj "/CN=Tuist Fleet MDM CA/O=Tuist"
```

Store as `scep-ca-cert-pem` / `scep-ca-key-pem`, then delete the local
files. Leave `push-topic`, `svc-account-password-hash-b64`, and
`bootstrap-pkg-b64` empty for now; they are produced by the ceremonies
below. After any 1Password change, re-run the deploy workflow (ESO
refreshes hourly but pods only pick up new values on restart).

### 1. APNs MDM push certificate (yearly!)

Apple Business Manager cannot issue MDM push certificates; the flow
still goes through the Apple Push Certificates Portal with a
vendor-signed CSR. For open-source MDMs the free CSR signer is
[mdmcert.download](https://mdmcert.download) (business use only,
best-effort availability).

1. Register at mdmcert.download with a tuist.dev address and confirm
   the email.
2. Generate the CSR + encryption keypair and submit (micromdm's
   `mdmctl` does all of it):
   `mdmctl mdmcert.download -new -email=you@tuist.dev`
3. The signed CSR arrives by email encrypted to the keypair;
   decrypt: `mdmctl mdmcert.download -decrypt=~/Downloads/mdm_signed_request.p7`
4. Sign in at <https://identity.apple.com/pushcert> — use a **Managed
   Apple Account from the ABM org**, not a personal Apple ID, so the
   cert isn't tied to an individual — and *Create a Certificate* with
   the decrypted CSR. Download the push certificate. Add a note on the
   portal entry ("tuist fleet MDM") — notes are the only way to tell
   certs apart later.
5. Upload cert + private key to nanomdm and record the topic it returns:

   ```bash
   cat push.pem push.key | curl --data-binary @- -X PUT \
     -u "nanomdm:$NANOMDM_API_KEY" https://mdm-staging.tuist.dev/v1/pushcert
   ```

6. Put the returned topic (`com.apple.mgmt.External.<uuid>`) into the
   1Password item as `push-topic` and re-deploy so the enrollment
   profile embeds it.

**Calendar the renewal now: the certificate expires after 1 year.** At
renewal time, generate a fresh signed CSR the same way, but click
**Renew** on the *existing* portal row — never *Create a Certificate*,
which mints a new topic and orphans every enrolled device. Same Apple
account, same row, then re-upload via `/v1/pushcert` (the topic stays
identical, nothing else changes).

### 2. ABM Management Services link (nanodep token exchange)

The ABM org exists (Apple Customer Number 1783103, verified;
Apple-direct purchases already land in inventory). What's missing is
the MDM server link. The nanodep "DEP name" used below is `tuist`.

1. Get nanodep's token-exchange public key:

   ```bash
   curl -u "depserver:$NANODEP_API_KEY" \
     "https://mdm-dep-staging.tuist.dev/v1/tokenpki/tuist" -o tuist-mdm.pem
   ```

2. In [business.apple.com](https://business.apple.com): your name in
   the sidebar → **Preferences** → **MDM Server Assignment / Your MDM
   Servers** → **Add**. Name it (e.g. `tuist-staging-mdm`), check
   *Allow this MDM Server to release devices*, upload `tuist-mdm.pem`.
3. Download the server token (`.p7m`). **It also expires after 1 year —
   calendar this too** (renew in ABM, re-run this step).
4. Feed the token to nanodep:

   ```bash
   curl -u "depserver:$NANODEP_API_KEY" -X PUT --data-binary @token.p7m \
     "https://mdm-dep-staging.tuist.dev/v1/tokenpki/tuist"
   ```

5. Verify: `curl -u "depserver:$NANODEP_API_KEY" https://mdm-dep-staging.tuist.dev/proxy/tuist/account`

### 3. DEP profile + default device assignment

1. Define the enrollment profile (via nanodep's transparent proxy to
   Apple). Save as `dep-profile.json`:

   ```json
   {
     "profile_name": "Tuist runner fleet",
     "url": "https://mdm-staging.tuist.dev/enroll?token=<enroll-token>",
     "org_magic": "dev.tuist.fleet",
     "is_supervised": true,
     "is_mandatory": true,
     "is_mdm_removable": false,
     "await_device_configured": true,
     "auto_advance_setup": true,
     "skip_setup_items": [
       "Accessibility", "Appearance", "AppleID", "Biometric",
       "DisplayTone", "FileVault", "iCloudDiagnostics", "iCloudStorage",
       "Location", "Payment", "Privacy", "Registration", "Restore",
       "ScreenTime", "Siri", "TermsOfAddress", "TOS", "UnlockWithWatch",
       "Welcome"
     ]
   }
   ```

   ```bash
   curl -u "depserver:$NANODEP_API_KEY" -X POST --data-binary @dep-profile.json \
     "https://mdm-dep-staging.tuist.dev/proxy/tuist/profile"
   ```

   Record the returned `profile_uuid`, then make it the auto-assign
   default for newly synced devices:

   ```bash
   curl -u "depserver:$NANODEP_API_KEY" -X PUT \
     -d "{\"profile_uuid\": \"$PROFILE_UUID\"}" \
     "https://mdm-dep-staging.tuist.dev/v1/assigner/tuist"
   ```

   (`auto_advance_setup` requires Ethernet, which the fleet always has;
   on macOS 15.4+ the "Set Up as New or Restore" pane cannot be hidden,
   but auto-advance walks through it.)

2. In ABM Preferences → **Default Device Assignment**, set **Mac** to
   the new MDM server, so future Apple-direct purchases assign
   themselves. depsyncer then assigns the stored profile UUID to each
   newly synced device with no further action.

### 4. Service account password hash

`AccountConfiguration` takes a `SALTED-SHA512-PBKDF2` ShadowHashData
blob, not a password. Generate (same construction as
macadmins/pycreateuserpkg):

```bash
python3 - <<'EOF'
import getpass, hashlib, os, plistlib, base64
password = getpass.getpass("service account password: ")
salt = os.urandom(32)
iterations = 39999
entropy = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, iterations, dklen=128)
blob = plistlib.dumps(
    {"SALTED-SHA512-PBKDF2": {"entropy": entropy, "salt": salt, "iterations": iterations}},
    fmt=plistlib.FMT_BINARY,
)
print(base64.b64encode(blob).decode())
EOF
```

Store the password itself and the printed base64 in the 1Password item
(`svc-account-password-hash-b64`).

### 5. Bootstrap package (build + sign)

Requires a **Developer ID Installer** identity (paid Apple Developer
Program). MDM-installed packages must be signed — `installd` rejects
unsigned ones — but do **not** need notarization (no quarantine bit on
MDM-initiated installs).

```bash
cd infra/mdm/pkg
./build.sh ~/path/to/fleet_ssh_key.pub "Developer ID Installer: Tuist GmbH (TEAMID)"
```

Put the printed `.b64` content into the 1Password item
(`bootstrap-pkg-b64`) and re-deploy. The enroller serves the decoded
pkg and computes the install manifest itself.

The postinstall deliberately uses `launchctl enable system/com.openssh.sshd`
+ `launchctl bootstrap` instead of `systemsetup -setremotelogin on`:
`systemsetup` demands Full Disk Access from its responsible process,
which an MDM-delivered postinstall does not reliably have; the launchd
route flips the same override with no TCC involvement.

### 6. Prototype M1 via Apple Configurator (provisional enrollment)

A refurb mini was not bought through our channel, so it enters ABM via
**Apple Configurator for iPhone** (not the Mac app): erase the Mac, and
at Setup Assistant scan the pairing screen with the Configurator iPhone
app. Requirements: Apple silicon or T2, macOS 12.0.1+. It then shows up
in ABM like a purchased device, picks up the default Mac assignment,
and ADE-enrolls supervised. Caveat: a **30-day provisional window**
(from successful enrollment) during which anyone with the device can
release it from ABM/supervision; it locks in after 30 days.

## Payloads and caveats

- **USB accessories** (`allowUSBRestrictedMode=false`,
  `com.apple.applicationaccess`, supervised-only): Mac *desktops* —
  including the minis — do not prompt for new accessories on current
  macOS; only Apple silicon laptops do. The payload is pushed anyway:
  it is harmless where inapplicable, covers any laptop that ever
  enrolls, and macOS 26 extends accessory approval state into Recovery.
- **Remote Login**: there is still no configuration-profile payload or
  DDM declaration for SSH on macOS (verified through macOS 26); the
  signed-package postinstall is the only MDM-deliverable path.
- **InstallEnterpriseApplication** validates the request and installs
  silently — failures are not reported back. The observable success
  signal is the machine becoming SSH-reachable; the validation
  checklist below probes exactly that.
- **macOS 26 note**: pkgs can also ship via DDM app management, which
  takes precedence — if we ever adopt DDM for packages, the
  InstallEnterpriseApplication of the same pkg will start failing.
  One mechanism at a time.
- **Bootstrap token**: escrow to MDM happens on the service account's
  *first GUI login*, not at creation (SSH does not count). Without it,
  MDM-driven OS updates on Apple silicon won't authorize. The
  acceptance checklist includes one Screen Sharing login per machine
  (or via the KVM) to escrow it. FileVault is off, so nothing else
  depends on it.
- **OS updates**: nanomdm is a protocol server; declarative update
  enforcement (deadlines) needs KMFDDM or equivalent on top. Out of
  scope for the pilot — major versions are DFU reprovisions, and minor
  update waves are orchestrated by the operator (cordon/drain) anyway.

## Validation checklist (physical M1, later)

1. Configurator provisional add → device appears in ABM, assigned to
   the MDM server automatically (depsyncer log shows the assignment).
2. Erase/restore → Setup Assistant runs through with zero interaction.
3. Login window reached; `ssh tuist@<ip>` works with the fleet key.
4. `pmset -g | grep autorestart` → 1; pull power, reapply → boots.
5. `profiles list` (via SSH, sudo) shows the enrollment + USB profiles.
6. One GUI login (Screen Sharing/KVM) → bootstrap token escrowed
   (`profiles status -type bootstraptoken`).
7. Unplug/replug a USB keyboard + the KVM → no approval prompt (also
   try after a reboot with the KVM attached from cold).
