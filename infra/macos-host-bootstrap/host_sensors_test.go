package bootstrap

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// node_exporter serves whatever the sensors job writes, so the two have to
// agree on the directory. The directory is created by the node_exporter step
// because it is the reader: a missing directory is a scrape error even on a
// host that runs no sensors job.
func TestRenderNodeExporterScript_ReadsTheHostSensorsTextfile(t *testing.T) {
	out := renderNodeExporterScript()
	created := false
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "sudo mkdir -p ") && strings.Contains(line, " "+hostSensorsDir) {
			created = true
		}
	}
	if !created {
		t.Fatalf("node_exporter script does not create %s\n%s", hostSensorsDir, out)
	}
	for _, want := range []string{
		"--collector.textfile \\",
		"--collector.textfile.directory=" + hostSensorsDir + " \\",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("node_exporter script missing %q\n%s", want, out)
		}
	}
}

func TestHostSensorsEnabled_RequiresBinaryNodeExporterAndTailnet(t *testing.T) {
	full := Config{
		HostSensorsBinary:  []byte("sensors"),
		NodeExporterBinary: []byte("node_exporter"),
		TailscaleAuthKey:   "auth-key",
	}
	if !hostSensorsEnabled(full) {
		t.Fatal("expected a fully wired config to enable the sensors job")
	}
	for name, mutate := range map[string]func(*Config){
		"no binary":        func(c *Config) { c.HostSensorsBinary = nil },
		"no node_exporter": func(c *Config) { c.NodeExporterBinary = nil },
		"no tailnet":       func(c *Config) { c.TailscaleAuthKey = "" },
	} {
		cfg := full
		mutate(&cfg)
		if hostSensorsEnabled(cfg) {
			t.Fatalf("expected the sensors job to be disabled with %s", name)
		}
	}
}

func TestRenderHostSensorsScript_InstallsASignedIntervalJob(t *testing.T) {
	out := renderHostSensorsScript(Config{HostSensorsBinary: []byte("sensors"), NodeExporterBinary: []byte("node_exporter")})
	for _, want := range []string{
		"sudo tee " + hostSensorsBinaryPath + " >/dev/null",
		"sudo codesign --force --sign - " + hostSensorsBinaryPath,
		"<string>" + hostSensorsBinaryPath + "</string>",
		"<string>--out=" + hostSensorsDir + "/host_sensors.prom</string>",
		"<key>StartInterval</key><integer>30</integer>",
		"<key>RunAtLoad</key><true/>",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("install script missing %q\n%s", want, out)
		}
	}
	if strings.Contains(out, "KeepAlive") {
		t.Fatalf("the sensors job runs once per interval; KeepAlive would relaunch it in a loop\n%s", out)
	}
}

// Turning it off has to remove the job, and the readings with it: a stale file
// left behind would keep being served as current by node_exporter.
func TestRenderHostSensorsScript_UninstallsWhenNotConfigured(t *testing.T) {
	out := renderHostSensorsScript(Config{NodeExporterBinary: []byte("node_exporter")})
	for _, want := range []string{
		"launchctl bootout system \"$PLIST\"",
		"rm -f \"$PLIST\"",
		"rm -f " + hostSensorsBinaryPath,
		"rm -f " + hostSensorsDir + "/host_sensors.prom",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("disabled render missing %q\n%s", want, out)
		}
	}
	if strings.Contains(out, "launchctl bootstrap") {
		t.Fatalf("disabled render must not load the job\n%s", out)
	}
	if strings.Contains(out, "rm -rf "+hostSensorsDir) {
		t.Fatalf("the directory belongs to node_exporter's textfile collector and must stay\n%s", out)
	}
}

func TestRenderHostSensorsScripts_AreValidSh(t *testing.T) {
	for name, body := range map[string]string{
		"install":   renderHostSensorsScript(Config{HostSensorsBinary: []byte("sensors"), NodeExporterBinary: []byte("node_exporter")}),
		"uninstall": renderHostSensorsScript(Config{}),
	} {
		script := filepath.Join(t.TempDir(), name)
		if err := os.WriteFile(script, []byte(body), 0o600); err != nil {
			t.Fatalf("write script: %v", err)
		}
		if combined, err := exec.Command("sh", "-n", script).CombinedOutput(); err != nil {
			t.Fatalf("%s script is not valid sh: %v\n%s", name, err, combined)
		}
	}
}

// Shipping the job, re-baking it and removing it all have to move the fleet
// hash, or the change never reaches an already-bootstrapped mini.
func TestHostConfigHash_ChangesWithHostSensors(t *testing.T) {
	base := Config{
		TartKubeletBinary:  []byte("kubelet-v1"),
		NodeExporterBinary: []byte("node_exporter"),
	}
	with := base
	with.HostSensorsBinary = []byte("sensors-v1")
	if HostConfigHash(base) == HostConfigHash(with) {
		t.Fatal("HostConfigHash must change when the sensors job is added")
	}
	rebuilt := with
	rebuilt.HostSensorsBinary = []byte("sensors-v2")
	if HostConfigHash(with) == HostConfigHash(rebuilt) {
		t.Fatal("HostConfigHash must change when the sensors binary is re-baked")
	}
}
