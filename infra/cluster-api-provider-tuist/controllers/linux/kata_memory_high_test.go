package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// The tuist-kata-memory-high service (b300ad91da) could not reclaim guest RAM,
// which is shmem, and was replaced by sizing podFixed with the guest. The
// repair has to take it off the hosts that already run it.
func TestKataHostConfigRepairRemovesMemoryHighService(t *testing.T) {
	script := renderKataHostConfigRepairScript(linuxCloudInitOptions{BootstrapUser: "ubuntu"})
	for _, want := range []string{
		"systemctl disable --now tuist-kata-memory-high.service",
		"rm -f /etc/systemd/system/tuist-kata-memory-high.service /usr/local/sbin/tuist-kata-memory-high",
	} {
		if !strings.Contains(script, want) {
			t.Errorf("repair script is missing %q", want)
		}
	}
	if strings.Contains(script, "systemctl restart tuist-kata-memory-high.service") {
		t.Error("repair script still starts tuist-kata-memory-high")
	}
}

func TestKataMemoryHighResetLiftsOnlyTheServicesSoftLimit(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "kubepods.slice")
	const gib = 1 << 30
	pod := func(slice string, max, high int) string {
		t.Helper()
		path := filepath.Join(root, slice)
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
		for file, value := range map[string]int{"memory.max": max, "memory.high": high} {
			if err := os.WriteFile(filepath.Join(path, file), []byte(strconv.Itoa(value)+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		return path
	}
	// Set by the service: memory.max less its 256 MiB headroom.
	softLimited := pod("kubepods-pod1.slice", 70*gib, 70*gib-256<<20)
	// Set by something else; not ours to lift.
	other := pod("kubepods-pod2.slice", 40*gib, 30*gib)

	script := filepath.Join(dir, "reset")
	if err := os.WriteFile(script, []byte(kataMemoryHighResetScript), 0o755); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("/bin/sh", script, root).CombinedOutput(); err != nil {
		t.Fatalf("reset failed: %v\n%s", err, out)
	}
	read := func(path string) string {
		t.Helper()
		b, err := os.ReadFile(filepath.Join(path, "memory.high"))
		if err != nil {
			t.Fatal(err)
		}
		return strings.TrimSpace(string(b))
	}
	if got := read(softLimited); got != "max" {
		t.Errorf("soft-limited Pod memory.high = %s, want max", got)
	}
	if got, want := read(other), strconv.Itoa(30*gib); got != want {
		t.Errorf("other Pod memory.high = %s, want it left at %s", got, want)
	}
}
