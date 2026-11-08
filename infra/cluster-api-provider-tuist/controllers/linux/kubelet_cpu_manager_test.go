package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The re-push restarts kubelet on every Kata node at once. A kubelet whose
// config names a different CPU manager policy than its checkpoint does not
// start, so the setup must keep shared CPUs on a node whose checkpoint predates
// the static policy, and only switch a node that has no checkpoint or already
// runs static.
func TestKubeletCPUManagerSetup(t *testing.T) {
	sharedConfig := kubeletConfigContent("10.96.0.10", kubeletClientCAPath, false)
	staticConfig := kubeletConfigContent("10.96.0.10", kubeletClientCAPath, true)
	for _, tc := range []struct {
		name       string
		checkpoint string
		wantStatic bool
	}{
		{name: "fresh node switches to static", wantStatic: true},
		{name: "node already on static stays static", checkpoint: `{"policyName":"static","defaultCpuSet":"0-31","checksum":1}`, wantStatic: true},
		{name: "node joined under none keeps shared CPUs", checkpoint: `{"policyName":"none","defaultCpuSet":"","checksum":1}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			kubeletDir := filepath.Join(dir, "kubelet")
			topology := filepath.Join(dir, "cpu", "cpu0", "topology")
			for _, d := range []string{kubeletDir, topology} {
				if err := os.MkdirAll(d, 0755); err != nil {
					t.Fatal(err)
				}
			}
			// cpu0's sibling is not cpu1 on this box, as on a Ryzen 9950X.
			if err := os.WriteFile(filepath.Join(topology, "thread_siblings_list"), []byte("0,16\n"), 0644); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(kubeletDir, "config.yaml"), []byte(staticConfig), 0644); err != nil {
				t.Fatal(err)
			}
			if tc.checkpoint != "" {
				if err := os.WriteFile(filepath.Join(kubeletDir, "cpu_manager_state"), []byte(tc.checkpoint), 0644); err != nil {
					t.Fatal(err)
				}
			}
			shim := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$TEST_DIR/systemctl.log\"\n"
			if err := os.WriteFile(filepath.Join(dir, "systemctl"), []byte(shim), 0755); err != nil {
				t.Fatal(err)
			}
			// The replacer also rewrites the CA path inside the embedded shared
			// config, so the expectation below goes through it too.
			hostPaths := strings.NewReplacer(
				"/var/lib/kubelet", kubeletDir,
				"/sys/devices/system/cpu", filepath.Join(dir, "cpu"),
			)
			script := hostPaths.Replace(kubeletCPUManagerSetup("", sharedConfig))
			cmd := exec.Command("/bin/bash", "-s")
			cmd.Stdin = strings.NewReader(script)
			cmd.Env = append(os.Environ(), "PATH="+dir+":/usr/bin:/bin", "TEST_DIR="+dir)
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("err=%v output=%s", err, out)
			}

			config, err := os.ReadFile(filepath.Join(kubeletDir, "config.yaml"))
			if err != nil {
				t.Fatal(err)
			}
			systemctl, _ := os.ReadFile(filepath.Join(dir, "systemctl.log"))
			if !tc.wantStatic {
				if string(config) != hostPaths.Replace(sharedConfig) {
					t.Fatalf("config = %q, want the shared-CPU config", config)
				}
				if len(systemctl) != 0 {
					t.Fatalf("system.slice must stay unpinned while the node runs shared CPUs, got %q", systemctl)
				}
				return
			}
			want := strings.Replace(staticConfig, reservedSystemCPUsPlaceholder, "0,16", 1)
			if string(config) != want {
				t.Fatalf("config = %q, want %q", config, want)
			}
			if got := strings.TrimSpace(string(systemctl)); got != "set-property system.slice AllowedCPUs=0,16" {
				t.Fatalf("systemctl = %q", got)
			}
		})
	}
}
