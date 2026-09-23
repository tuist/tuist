package bootstrap

import (
	"bytes"
	"context"
	"fmt"

	"golang.org/x/crypto/ssh"
)

const (
	hostSensorsBinaryPath = "/usr/local/bin/tuist-host-sensors"
	// Written by the sensors job and read by node_exporter's textfile
	// collector, so the readings ride the node_exporter scrape: no port, no
	// egress Service, no tailnet grant of their own.
	hostSensorsDir   = "/var/lib/tuist-host-sensors"
	hostSensorsLabel = "dev.tuist.host-sensors"
)

// hostSensorsConfigured reports whether the operator image carries the sensors
// job and a node_exporter to serve what it writes. Like logShippingConfigured,
// it leaves TailscaleAuthKey out: HostConfigHash zeroes that secret, and a
// render that consulted it would hash enabled and disabled alike.
func hostSensorsConfigured(cfg Config) bool {
	return len(cfg.HostSensorsBinary) > 0 && len(cfg.NodeExporterBinary) > 0
}

// hostSensorsEnabled adds node_exporter's own runtime gate: without a tailnet
// node_exporter is not installed, and nothing would read the file.
func hostSensorsEnabled(cfg Config) bool {
	return hostSensorsConfigured(cfg) && cfg.TailscaleAuthKey != ""
}

// installHostSensors converges the host onto the desired state, removing the
// job when it is off for the reason installLogShipper does: skipping the
// install would leave a loaded job running.
func installHostSensors(ctx context.Context, client *ssh.Client, cfg Config) error {
	if !hostSensorsEnabled(cfg) {
		return RunCommand(ctx, client, renderHostSensorsUninstallScript())
	}
	return RunCommandWithStdin(ctx, client, renderHostSensorsInstallScript(), bytes.NewReader(cfg.HostSensorsBinary))
}

// renderHostSensorsScript is the half HostConfigHash folds in: install when
// configured, uninstall otherwise, so turning it off moves the hash too.
func renderHostSensorsScript(cfg Config) string {
	if !hostSensorsConfigured(cfg) {
		return renderHostSensorsUninstallScript()
	}
	return renderHostSensorsInstallScript()
}

// renderHostSensorsUninstallScript removes the job and its last readings,
// which node_exporter would otherwise keep serving as current. The directory
// stays: node_exporter's textfile collector reads it on every host.
func renderHostSensorsUninstallScript() string {
	return fmt.Sprintf(`set -euo pipefail
PLIST=/Library/LaunchDaemons/%[1]s.plist
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo rm -f "$PLIST"
sudo rm -f %[2]s
sudo rm -f %[3]s/host_sensors.prom
`, hostSensorsLabel, hostSensorsBinaryPath, hostSensorsDir)
}

// renderHostSensorsInstallScript installs the binary from stdin and a launchd
// job that runs it every 30 seconds. It samples once and exits, so a crash
// costs one sample and never a wedged daemon; node_exporter is scraped once a
// minute, so every scrape sees a sample at most 30 seconds old.
//
// The reload is the log shipper's: compare the plist and kickstart an
// unchanged job rather than re-registering it, because Background Task
// Management stops honouring a job that re-registers too often.
func renderHostSensorsInstallScript() string {
	return fmt.Sprintf(`set -euo pipefail
sudo mkdir -p /usr/local/bin %[3]s
sudo tee %[2]s >/dev/null
sudo chmod 0755 %[2]s
# Re-sign in place, as for tart-kubelet: overwriting the binary at the same
# inode leaves AMFI checking the new pages against the old cdhash.
sudo codesign --force --sign - %[2]s

PLIST=/Library/LaunchDaemons/%[1]s.plist
NEW="$(mktemp)"
trap 'rm -f "$NEW"' EXIT
cat >"$NEW" <<'HOSTSENSORS_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>%[1]s</string>
  <key>ProgramArguments</key>
  <array>
    <string>%[2]s</string>
    <string>--out=%[3]s/host_sensors.prom</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>/var/log/tuist-host-sensors.log</string>
  <key>StandardErrorPath</key><string>/var/log/tuist-host-sensors.log</string>
</dict>
</plist>
HOSTSENSORS_PLIST

if cmp -s "$NEW" "$PLIST" && sudo launchctl print system/%[1]s >/dev/null 2>&1; then
  sudo launchctl kickstart -k system/%[1]s 2>/dev/null || true
else
  sudo cp "$NEW" "$PLIST"
  sudo chown root:wheel "$PLIST"
  sudo chmod 0644 "$PLIST"
  sudo launchctl bootout system "$PLIST" 2>/dev/null || true
  sudo launchctl bootstrap system "$PLIST" 2>/dev/null || true
fi
`, hostSensorsLabel, hostSensorsBinaryPath, hostSensorsDir)
}
