package linux

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

func TestKataVirtiofsSetup(t *testing.T) {
	for _, tc := range []struct {
		name      string
		sysctl    string
		wantError bool
	}{
		{name: "raises nr_open then installs the drop-in", sysctl: "apply"},
		// virtiofsd exits when --rlimit-nofile exceeds fs.nr_open, which would fail
		// every new Kata pod, so the drop-in must never land without the sysctl.
		{name: "refused sysctl leaves Kata defaults", sysctl: "noop", wantError: true},
		{name: "failed sysctl leaves Kata defaults", sysctl: "fail", wantError: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			nrOpen := filepath.Join(dir, "nr_open")
			if err := os.WriteFile(nrOpen, []byte("1048576\n"), 0600); err != nil {
				t.Fatal(err)
			}
			// Point the host paths into the temporary directory and replace
			// sysctl, so the real script runs without touching the test host.
			shim := `#!/bin/sh
[ "$1" = -p ] || exit 2
[ "$TEST_SYSCTL" != fail ] || exit 1
[ "$TEST_SYSCTL" = noop ] || sed -n 's/^fs.nr_open = //p' "$2" > "$TEST_DIR/nr_open"
`
			if err := os.WriteFile(filepath.Join(dir, "sysctl"), []byte(shim), 0755); err != nil {
				t.Fatal(err)
			}
			script := strings.NewReplacer(
				"/etc/sysctl.d", filepath.Join(dir, "sysctl.d"),
				"/opt/kata", filepath.Join(dir, "kata"),
				"/proc/sys/fs/nr_open", nrOpen,
			).Replace(kataVirtiofsSetup(""))
			if err := os.MkdirAll(filepath.Join(dir, "sysctl.d"), 0755); err != nil {
				t.Fatal(err)
			}
			cmd := exec.Command("/bin/bash", "-s")
			cmd.Stdin = strings.NewReader(script)
			cmd.Env = append(os.Environ(), "PATH="+dir+":/usr/bin:/bin", "TEST_DIR="+dir, "TEST_SYSCTL="+tc.sysctl)
			out, err := cmd.CombinedOutput()
			if (err != nil) != tc.wantError {
				t.Fatalf("err=%v output=%s", err, out)
			}

			dropIn := filepath.Join(dir, strings.TrimPrefix(kataVirtiofsDropInPath, "/opt/"))
			written, err := os.ReadFile(dropIn)
			if tc.wantError {
				if err == nil {
					t.Fatalf("drop-in installed although fs.nr_open was not raised: %s", written)
				}
				return
			}
			if string(written) != kataVirtiofsDropIn {
				t.Fatalf("drop-in = %q, err=%v", written, err)
			}
			raised, _ := os.ReadFile(nrOpen)
			if strings.TrimSpace(string(raised)) != fmt.Sprint(kataVirtiofsFileLimit) {
				t.Fatalf("fs.nr_open = %q", raised)
			}
		})
	}
}

func TestKataVirtiofsDropInKeepsKataDefaults(t *testing.T) {
	for _, want := range []string{
		"[hypervisor.qemu]",
		`"--thread-pool-size=1"`,
		`"--announce-submounts"`,
		fmt.Sprintf(`"--rlimit-nofile=%d"`, kataVirtiofsFileLimit),
	} {
		if !strings.Contains(kataVirtiofsDropIn, want) {
			t.Errorf("drop-in is missing %s", want)
		}
	}
	if kataVirtiofsFileLimit <= 1000000 {
		t.Fatal("the budget must exceed virtiofsd's default of min(1000000, fs.nr_open)")
	}
}

func TestKataHostConfigRevisionCoversVirtiofs(t *testing.T) {
	node := &corev1.Node{}
	node.Status.NodeInfo.BootID = "boot"
	before := kataHostConfigRevision(node)
	original := kataVirtiofsDropIn
	t.Cleanup(func() { kataVirtiofsDropIn = original })
	kataVirtiofsDropIn += "# changed\n"
	if kataHostConfigRevision(node) == before {
		t.Fatal("changing the virtiofsd drop-in must re-run the repair on existing hosts")
	}
}

func TestKataHostConfigRepairInstallsVirtiofs(t *testing.T) {
	script := renderKataHostConfigRepairScript(linuxCloudInitOptions{BootstrapUser: "ubuntu"})
	for _, want := range []string{kataVirtiofsSysctl, kataVirtiofsDropIn} {
		if !strings.Contains(script, want) {
			t.Errorf("repair script is missing %q", want)
		}
	}
}
