package bootstrap

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"golang.org/x/crypto/ssh"
)

// tartLayout is where Tart lives on a host.
type tartLayout struct {
	// Root holds one directory per installed version, each with the
	// release's tart.app inside.
	Root string
	// Legacy is where hosts bootstrapped before versioned installs keep their
	// Tart. It is pruned like any other version once nothing runs from it.
	Legacy string
	// Wrapper is the `tart` on PATH that every caller runs.
	Wrapper string
}

var hostTartLayout = tartLayout{
	Root:    "/usr/local/lib/tart",
	Legacy:  "/usr/local/lib/tart.app",
	Wrapper: "/usr/local/bin/tart",
}

var tartVersionPattern = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)

// ValidTartVersion reports whether version has the shape `tart --version`
// prints, which is also what installTart interpolates into host paths.
func ValidTartVersion(version string) bool {
	return tartVersionPattern.MatchString(version)
}

// installTart makes version the Tart that /usr/local/bin/tart runs.
//
// Each version gets its own bundle under the layout's root and the wrapper is
// switched to it with a rename, so the bundle a running `tart run` was started
// from is never written to or removed: on a host with VMs in flight, those VMs
// keep running on the old version and every new `tart` invocation, including
// the `tart stop` and `tart delete` that end them, uses the new one. Tart keeps
// its VM directory layout across the versions the fleet runs (see "Tart
// versions" in infra/tart-kubelet/AGENTS.md), so either version can manage the
// other's VMs.
//
// The tarball is only streamed when the host runs a different version. Old
// bundles are removed once no process runs from them; one still in use is kept
// until a later install.
//
// Why a wrapper script instead of a symlink: Tart's
// Virtualization.framework entitlements are scoped to the .app
// bundle's signature, so the executable has to be invoked through its
// bundle path. The wrapper hides that path detail from callers
// (tart-kubelet, operators SSHing in to debug) which all want a
// stable `tart` on PATH.
func installTart(ctx context.Context, client *ssh.Client, version string, tarball []byte) error {
	if len(tarball) == 0 {
		return fmt.Errorf("tart tarball is empty")
	}
	if !ValidTartVersion(version) {
		return fmt.Errorf("invalid tart version %q", version)
	}
	installed, err := RunCommandOutput(ctx, client, renderTartVersionProbeScript(hostTartLayout), nil)
	if err != nil {
		return fmt.Errorf("read installed tart version: %w", err)
	}
	if installed := strings.TrimSpace(installed); installed != version {
		if err := RunCommandWithStdin(ctx, client, renderTartInstallScript(hostTartLayout, version), bytes.NewReader(tarball)); err != nil {
			return fmt.Errorf("install tart %s over %q: %w", version, installed, err)
		}
	}
	if err := RunCommand(ctx, client, renderTartPruneScript(hostTartLayout)); err != nil {
		return fmt.Errorf("prune unused tart bundles: %w", err)
	}
	return nil
}

// renderTartVersionProbeScript prints the version the wrapper runs, or nothing
// when it cannot run: no wrapper yet, or one pointing at a removed bundle.
func renderTartVersionProbeScript(l tartLayout) string {
	return l.Wrapper + " --version 2>/dev/null || true\n"
}

// renderTartInstallScript extracts the tarball on stdin beside the installed
// versions, checks it holds version, and points the wrapper at it. A version
// directory that already holds a bundle is reused rather than replaced, since
// VMs may still be running from it.
func renderTartInstallScript(l tartLayout, version string) string {
	return fmt.Sprintf(`set -euo pipefail
dest=%[1]s/%[2]s
stage=%[1]s/.%[2]s.partial
sudo mkdir -p %[1]s "$(dirname %[3]s)"
sudo rm -rf "$stage"
sudo mkdir "$stage"
sudo tar -xzf - -C "$stage"
got="$("$stage/tart.app/Contents/MacOS/tart" --version)"
if [ "$got" != %[2]s ]; then
  sudo rm -rf "$stage"
  echo "the tarball holds Tart $got, not %[2]s" >&2
  exit 1
fi
if [ -x "$dest/tart.app/Contents/MacOS/tart" ]; then
  sudo rm -rf "$stage"
else
  sudo rm -rf "$dest"
  sudo mv "$stage" "$dest"
fi
sudo tee %[3]s.new >/dev/null <<'EOF'
#!/bin/sh
exec %[1]s/%[2]s/tart.app/Contents/MacOS/tart "$@"
EOF
sudo chmod 0755 %[3]s.new
sudo mv -f %[3]s.new %[3]s
test "$(%[3]s --version)" = %[2]s
`, l.Root, version, l.Wrapper)
}

// renderTartPruneScript removes every Tart bundle except the one the wrapper
// runs and any a process still runs from. It reads the current bundle from the
// wrapper rather than taking a version, so it never removes the bundle of a
// host still on the legacy path. A pgrep that fails for any reason other than
// finding nothing keeps the bundle.
func renderTartPruneScript(l tartLayout) string {
	return fmt.Sprintf(`set -euo pipefail
current="$(sed -n 's|^exec \(.*\)/Contents/MacOS/tart .*|\1|p' %[3]s 2>/dev/null || true)"
if [ -z "$current" ]; then
  echo "cannot read the bundle %[3]s runs; pruning nothing" >&2
  exit 0
fi
{ echo %[2]s; find %[1]s -mindepth 1 -maxdepth 1 2>/dev/null || true; } | while IFS= read -r dir; do
  [ -e "$dir" ] || continue
  case "$current" in
    "$dir"|"$dir"/*) continue ;;
  esac
  rc=0
  sudo -n pgrep -f "^$dir/" >/dev/null || rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "keeping $dir: a process still runs from it"
    continue
  fi
  sudo rm -rf "$dir"
done
`, l.Root, l.Legacy, l.Wrapper)
}

// TartReleaseFile is the name of a release's tarball inside its version
// directory, as the operator image lays them out: <dir>/<version>/tart.tar.gz.
const TartReleaseFile = "tart.tar.gz"

// LoadTartReleases reads every Tart release under dir, keyed by version. A
// directory whose name is not a version is an error rather than skipped, so a
// mislabelled release cannot silently go missing from the image.
func LoadTartReleases(dir string) (map[string][]byte, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	releases := map[string][]byte{}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if !ValidTartVersion(entry.Name()) {
			return nil, fmt.Errorf("%s is not a Tart version", filepath.Join(dir, entry.Name()))
		}
		tarball, err := os.ReadFile(filepath.Join(dir, entry.Name(), TartReleaseFile))
		if err != nil {
			return nil, err
		}
		if len(tarball) == 0 {
			return nil, fmt.Errorf("%s is empty", filepath.Join(dir, entry.Name(), TartReleaseFile))
		}
		releases[entry.Name()] = tarball
	}
	if len(releases) == 0 {
		return nil, fmt.Errorf("no Tart releases in %s", dir)
	}
	return releases, nil
}
