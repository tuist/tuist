# Desktop distribution

Linux x86_64 AppImage and Windows x86_64 per-user NSIS are packaged with
**cargo-packager 0.11.7**, from native **Once** outputs. The GPUI upgrade needs
Once's `build_script_sources` support and its build-script debug-assertions fix,
both included in Once 0.77.5 and later (the workspace pins 0.81.1). The latter enables GPUI's build script
to generate embedded Windows shaders for optimized builds.
The existing Swift
macOS app, DMG release and Sparkle feed are unchanged. macOS is a development
and graph-qualification host, not a packaging target here.

## Build and inspect

Use Bash (Git Bash on Windows), jq, mikefarah yq, OpenSSL, the native dependencies
listed in `code.yml`, Once and Rust from `code/mise.toml`, cargo-packager
0.11.7 and minisign. jq and yq are pinned in mise. Installing the
packager tool with `cargo install --locked cargo-packager --version '=0.11.7'`
does not build the application. Ubuntu 22.04 has no minisign package; CI uses
`install-minisign.sh DESTINATION` to install upstream Minisign 0.12 with a pinned
SHA-256 checksum, keeping the Ubuntu 22.04 build baseline. Native CI checkouts
include only `code/` and the shared navigation fixtures to avoid unrelated
Swift fixture paths exceeding Windows checkout limits.
The desktop workflows exclude the root `mise.toml` via
`MISE_IGNORED_CONFIG_PATHS` so monorepo tools and post-install hooks are not
inherited. Run packaging through `mise exec` so pinned tool paths remain
available when the build changes into its staging directory outside the checkout.
From `code/`, on native Linux/Windows x86_64:

```sh
for test in distribution/test_*.sh; do bash "$test"; done
ONCE_CACHE_PROVIDER=local mise exec -- bash distribution/release.sh build --output /absolute/new/staging
bash distribution/smoke.sh /absolute/new/staging
```

The Windows install/uninstall smoke requires `CI=true` and refuses an existing
installation. Run only on a disposable host. The Linux smoke extracts the real
AppImage and checks its launcher, icon and `tuist:` MIME handler. Neither smoke
is proof of GPU rendering or a complete N → N+1 update/restart.

The staging directory must not exist. It contains:

- `source/`: private source-only copy, locked vendor sources and its own local
  `.once/` cache. Never upload this directory or reuse another run's cache.
- `bin/TuistCode[.exe]`: copied from the actual Once-declared
  `.once/out/cargo_tuist_desktop_bin_TuistCode/TuistCode[.exe]` output after build/tests.
- `packager.json`: explicit pinned-schema config, without build hooks; `icon.png`
  and a PNG-backed Windows ICO generated from the real 256px brand icon.
- `packages/`: native packages, not assumed Cargo `target/release` products.
- `assets/`: final raw `.AppImage` or NSIS `.exe`, optional `.sig`, and a platform
  record (`linux-x86_64.json` / `windows-x86_64.json`). Unsigned CI records cannot
  generate a release feed.

### Once optimization qualification

The pinned Once has **no `build --release`**. `query schema cargo_workspace` only offers
`dep_rustc_flags` for external dependencies. The pinned `rust.star` implements
`_rust_user_flags` from each Rust target's `rustc_flags`; it does not turn a
Cargo release profile or ambient `RUSTFLAGS` into first-party compiler flags.

`release.sh` queries Once's generated first-party targets, preserves their
attributes/dependency aliases/test roots, and writes explicit private target
declarations with `-C opt-level=3 -C debuginfo=0` on **every first-party target**.
The private graph uses `cargo_dependencies` with the same flags for external
crates. That schema requires vendored source trees, so `cargo vendor --locked
--versioned-dirs` only fetches/copies locked source; it never compiles the app.
Staged sources run `once test --all` before this graph rewrite, with debug
assertions enabled: GPUI's keyboard/layout tests need its debug-only bounds
instrumentation. A test failure stops packaging and prints the libtest logs.
The graph is validated and each first-party flag set is read back before
`once build cargo_tuist_desktop_bin_TuistCode`. Build scripts
receive `OPT_LEVEL=3`, `DEBUG=false`; Once's `PROFILE` remains `debug`, not Cargo's
release profile. This is an optimized Once build, not a claim of Cargo Release
profile parity, LTO, stripping, or deterministic/reproducible output.

## Installation identity and protocol

The sole registered URL scheme is **`tuist:`**, never HTTP/HTTPS. NSIS's pinned
template owns per-user registry registration, Start Menu/desktop shortcuts and
uninstall cleanup. `installMode=currentUser`, `productName=Tuist Code` defaults to
`%LOCALAPPDATA%\Tuist Code`, with `TuistCode.exe`, `uninstall.exe`, and the installer-owned
adjacent resource **`tuist-installation` containing `nsis\n`**. This is the backend
contract. The upstream installer allows a user-chosen directory; the current
backend deliberately disables updates outside the default location. Do not
relax that check merely to support copied executables. NSIS `appdataPaths` is
unset, so uninstall does not offer deletion of shared Tuist credentials.

The pinned template's protocol-uninstall guard uses compile-time `!if` against
runtime `$R7`. `nsis-hooks.nsh`, injected using the supported `preinstallSection`
field, supplies an `un.onUninstSuccess` callback with a runtime `${If}` instead.
It removes HKCU's protocol only when it still points to this installation.
Native Windows smoke requires protocol removal and credential retention.

Pinned `installer.nsi` `.onInstSuccess` handles **`/R` in silent/passive mode**.
Updater 0.2.3 invokes NSIS passively; backend `installer_args=["/R"]` is compatible.
Install only after gpui returns and the single-instance lock is dropped.

AppImage carries its `.desktop` entry, icon and `tuist:` handler; integration
with the user's desktop is explicit, not an install-time root side effect.
Use the repository's [AppImage integration helper](appimage.sh), available at
`code/distribution/appimage.sh` in a trusted checkout. Verify the AppImage's
release signature before invoking it, since integration extracts the executable:

```sh
chmod +x /absolute/path/to/TuistCode.AppImage
bash code/distribution/appimage.sh --install /absolute/path/to/TuistCode.AppImage
bash code/distribution/appimage.sh --uninstall
```

It installs into `$XDG_DATA_HOME/tuist-code-appimage` (default
`~/.local/share/tuist-code-appimage`), adds the icon/launcher and registers only
`tuist:`. Uninstall removes only that payload and its still-owned launcher/MIME
association, preserving replacement launchers, other handlers and account data.

`install-linux.sh` and `install-windows.ps1` are older **portable binary** helpers,
not production AppImage/NSIS installers. Such binaries and package-managed
builds have empty embedded package mode and must not self-update. Linux updater
additionally requires the AppImage runtime's `APPIMAGE`; Windows additionally
requires the installer marker, default install location and uninstaller.

## Signing and backend/feed contract

`build --release` requires `DESKTOP_UPDATE_PUBLIC_KEY` (base64 minisign public-key
box), `CARGO_PACKAGER_SIGN_PRIVATE_KEY` and
`CARGO_PACKAGER_SIGN_PRIVATE_KEY_PASSWORD` (present; may be empty for an
intentionally unencrypted key). It stamps only the private copy's
`crates/updater/src/public-key.txt` and `package-kind.txt` (`appimage`/`nsis`).
The package version comes from `[workspace.package].version`; every local
`tuist-*` Cargo.lock entry must agree. Missing key/input, lock drift, unsupported
host, wrong signing key or failed signature verification is fatal.

Windows release config additionally requires an approved Authenticode certificate
thumbprint in `DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT` and HTTPS RFC3161 timestamp
URL in `DESKTOP_WINDOWS_TIMESTAMP_URL`. The protected workflow imports a PFX
from `DESKTOP_WINDOWS_PFX_BASE64` / `DESKTOP_WINDOWS_PFX_PASSWORD`, checks its
identity/private key and removes it afterwards. Packager signs the app,
uninstaller and installer. The script checks the final installer's Windows trust
status, exact certificate and timestamp before minisign signing. Apple Developer
ID is not accepted as Windows signing configuration. Hardware/cloud-only signing
providers need a separately reviewed integration rather than substituting an
unapproved custom command.

```sh
mise exec -- bash distribution/release.sh build --release --output /absolute/new/staging
# Merge the two native assets/ directories into /absolute/assets first.
bash distribution/release.sh feed --assets /absolute/assets \
  --output /absolute/feed/latest.json --notes 'Release notes'
```

Feed generation verifies each payload signature and then signs **raw JSON
bytes**, producing **both `latest.json` and `latest.json.sig`**. `.sig` files are
the base64 signature-box contents emitted by `cargo-packager signer sign`, not
a filename or raw minisign box. The backend verifies the manifest before parsing
and downloads/verifies the selected payload before constructing/installing an
upstream update. Its static updater 0.2.3 schema is:

```json
{
  "version": "X.Y.Z",
  "notes": "Release notes",
  "platforms": {
    "linux-x86_64": {"url": "https://github.com/tuist/tuist/releases/download/desktop@X.Y.Z/TuistCode_X.Y.Z_x86_64.AppImage", "signature": "BASE64_SIGNATURE_BOX", "format": "appimage"},
    "windows-x86_64": {"url": "https://github.com/tuist/tuist/releases/download/desktop@X.Y.Z/TuistCode_X.Y.Z_x64-setup.exe", "signature": "BASE64_SIGNATURE_BOX", "format": "nsis"}
  }
}
```

Names above are illustrative: generation uses the actual packager output names.
Linux payload is the **raw AppImage**, NOT tar.gz. Updater 0.2.3's stale source
comment mentions tar.gz, but its implementation writes raw received bytes over
the AppImage. Sign those exact bytes.

## Internal previews only

The native jobs in `code.yml` are credential-free build/test/package/smoke CI for
Tuist Code. Its artifacts are internal previews, not public releases.
The public `desktop-release.yml` workflow has been removed. The signing/feed
scripts below remain offline tooling; no publication workflow invokes them.
Publishing or configuring distribution credentials requires separate approval
and native installed-app acceptance, including update/restart and credential
retention checks on Linux and Windows.

The publisher authenticates metadata and payloads again, refuses existing tags
or release drafts, creates/uploads/publishes `desktop@X.Y.Z` without marking it
repository latest, requires GitHub immutability, and downloads/compares every
immutable asset before replacing the two feed assets. API/network errors never
mean "tag absent". A partial version release requires operator recovery using
the original bytes, not rerunning with a different source under that version.
Replacing two feed assets is not atomic: readers must reject a transient
manifest/signature mismatch and retry later. A valid signed old feed is not a
freshness guarantee; signing does not independently prevent replay/freeze.

## Additional validation

```sh
for test in code/distribution/test_*.sh; do bash "$test"; done
shellcheck code/distribution/*.sh
actionlint .github/workflows/code.yml
```

With cargo-packager and minisign on PATH, the test suite also generates disposable
offline keys and validates actual signer interoperability/tamper rejection.
These tests do not provision real keys, publish, or prove Windows trust-chain
access, GPU behavior, or installed update/restart acceptance.
