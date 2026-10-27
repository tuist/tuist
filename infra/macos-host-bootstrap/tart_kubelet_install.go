package bootstrap

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"golang.org/x/crypto/ssh"
)

const tartKubeletPath = "/usr/local/bin/tart-kubelet"

// Config drift can change only a flag or a script. Check the actual executable,
// not the CR's last-applied SHA: a previous interrupted install may have damaged
// the file without ever updating that status.
func installTartKubelet(ctx context.Context, client *ssh.Client, binary []byte) error {
	if len(binary) == 0 {
		return fmt.Errorf("tart-kubelet binary is empty")
	}
	digest := sha256Hex(binary)
	installed, err := RunCommandOutput(ctx, client, renderTartKubeletProbeScript(tartKubeletPath, digest), nil)
	if err != nil {
		return fmt.Errorf("verify installed tart-kubelet: %w", err)
	}
	if strings.TrimSpace(installed) == "installed" {
		return nil
	}
	stdin := io.MultiReader(strings.NewReader(digest+"\n"), bytes.NewReader(binary))
	return RunCommandWithStdin(ctx, client, renderTartKubeletInstallScript(), stdin)
}

func renderTartKubeletProbeScript(path, digest string) string {
	return fmt.Sprintf(`set -eu
binary=%s
expected_sha=%s
if [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] &&
   [ "$(shasum -a 256 "$binary" | awk '{print $1}')" = "$expected_sha" ] &&
   codesign --verify --strict "$binary" >/dev/null 2>&1; then
  printf 'installed\n'
fi
`, shellQuote(path), shellQuote(digest))
}

// The manifest (SHA-256 followed by a newline) and binary ride stdin. The
// complete static protocol, including its watchdog, participates in drift.
func renderTartKubeletInstallScript() string {
	return renderTartKubeletInstallAt(tartKubeletPath, 300)
}

func renderTartKubeletInstallAt(path string, timeoutSeconds int) string {
	// Run the complete transaction as root. A private directory on the target
	// filesystem prevents symlink races and makes the final rename atomic. A
	// new inode also avoids AMFI's cached signature for the running executable;
	// preserve and verify the Go linker's signature instead of re-signing it.
	script := fmt.Sprintf(`set -eu
destination=%s
mkdir -p %s
stage=$(mktemp -d %s)
upload_pid=
watchdog_pid=
cleanup() {
  trap '' HUP INT TERM
  if [ -n "$upload_pid" ]; then
    kill "$upload_pid" 2>/dev/null || true
    wait "$upload_pid" 2>/dev/null || true
  fi
  if [ -n "$watchdog_pid" ]; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  rm -rf "$stage"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
installer_pid=$$
# An SSH disconnect does not reliably kill a sudo child. Bound the host-side
# writer independently of the operator's context and of the host's TCP timers.
(
  sleep %d &
  sleep_pid=$!
  trap 'kill "$sleep_pid" 2>/dev/null || true; wait "$sleep_pid" 2>/dev/null || true; exit' HUP INT TERM
  wait "$sleep_pid"
  echo 'tart-kubelet install exceeded its host-side deadline' >&2
  kill -TERM "$installer_pid" 2>/dev/null || true
) &
watchdog_pid=$!
IFS= read -r expected_sha
case "$expected_sha" in
  ''|*[!0-9a-f]*) echo 'invalid tart-kubelet SHA-256 manifest' >&2; exit 1 ;;
esac
[ "${#expected_sha}" -eq 64 ]
# POSIX shells replace background commands' stdin with /dev/null. Preserve
# the upload stream before launching the writer so the watchdog can bound it.
exec 3<&0
cat <&3 > "$stage/tart-kubelet" &
upload_pid=$!
wait "$upload_pid"
upload_pid=
actual_sha=$(shasum -a 256 "$stage/tart-kubelet" | awk '{print $1}')
if [ "$actual_sha" != "$expected_sha" ]; then
  echo "tart-kubelet upload checksum mismatch: expected $expected_sha, got $actual_sha" >&2
  exit 1
fi
chmod 0755 "$stage/tart-kubelet"
codesign --verify --strict "$stage/tart-kubelet"
mv -f "$stage/tart-kubelet" "$destination"
`, shellQuote(path), shellQuote(filepath.Dir(path)), shellQuote(filepath.Join(filepath.Dir(path), ".tart-kubelet.XXXXXXXX")), timeoutSeconds)
	return "sudo -n /bin/sh -c " + shellQuote(script)
}
